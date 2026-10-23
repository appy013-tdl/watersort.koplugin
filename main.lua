local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local RenderText = require("ui/rendertext")
local Screen = Device.screen
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local CAPACITY = 4
local EMPTY_BOTTLES = 2
local MAX_UNDOS = 5
local MAX_EXTRA_BOTTLES = 1
local SETTINGS_KEY = "watersort_game_state"

-- Pattern Metadata (1 to 10)
local PATTERNS = {
    { id = 1, label = "1", name = "Solid" },
    { id = 2, label = "2", name = "H-Stripes" },
    { id = 3, label = "3", name = "V-Stripes" },
    { id = 4, label = "4", name = "Dots" },
    { id = 5, label = "5", name = "Checker" },
    { id = 6, label = "6", name = "Diag //" },
    { id = 7, label = "7", name = "Diag \\\\" },
    { id = 8, label = "8", name = "Grid #" },
    { id = 9, label = "9", name = "Bricks" },
    { id = 10, label = "0", name = "Rings" },
}

--------------------------------------------------------------------------------
-- Combinatorial Level Generator (Deterministic Seeded Permutations)
--------------------------------------------------------------------------------
local LevelGenerator = {}

function LevelGenerator.getPatternCount(level)
    if level <= 2 then return 4
    elseif level <= 6 then return 5
    elseif level <= 12 then return 6
    elseif level <= 20 then return 7
    elseif level <= 35 then return 8
    elseif level <= 55 then return 9
    else return 10 end
end

function LevelGenerator.makeRNG(seed)
    local state = (seed * 1103515245 + 12345) % 2147483648
    if state == 0 then state = 1 end
    return function(max_val)
        state = (state * 1103515245 + 12345) % 2147483648
        return (state % max_val) + 1
    end
end

function LevelGenerator.generate(level)
    local num_patterns = LevelGenerator.getPatternCount(level)
    local rng = LevelGenerator.makeRNG(level * 7919 + num_patterns * 101)

    -- 1. Build the multiset pool of 4 * N liquid units
    local pool = {}
    for p = 1, num_patterns do
        for _ = 1, CAPACITY do
            table.insert(pool, p)
        end
    end

    -- 2. Perform Fisher-Yates shuffle to generate a permutation
    for i = #pool, 2, -1 do
        local j = rng(i)
        pool[i], pool[j] = pool[j], pool[i]
    end

    -- 3. Distribute into N bottles of capacity 4
    local bottles = {}
    local idx = 1
    for b = 1, num_patterns do
        bottles[b] = {}
        for c = 1, CAPACITY do
            bottles[b][c] = pool[idx]
            idx = idx + 1
        end
    end

    -- 4. Prevent any bottle from starting already solved (all 4 identical)
    for b = 1, num_patterns do
        local first = bottles[b][1]
        local all_same = true
        for c = 2, CAPACITY do
            if bottles[b][c] ~= first then
                all_same = false
                break
            end
        end
        if all_same then
            local next_b = (b % num_patterns) + 1
            bottles[b][CAPACITY], bottles[next_b][1] = bottles[next_b][1], bottles[b][CAPACITY]
        end
    end

    -- 5. Add empty helper bottles
    for _ = 1, EMPTY_BOTTLES do
        table.insert(bottles, {})
    end

    return bottles
end

--------------------------------------------------------------------------------
-- Custom Board Widget: Draws Bottles, Patterns, & Handles Touch Input
--------------------------------------------------------------------------------
local BottleBoardWidget = InputContainer:extend{
    game_dialog = nil,
    width = 0,
    height = 0,
}

function BottleBoardWidget:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.bottle_rects = {}
    self.label_face = Font:getFace("cfont", Screen:scaleBySize(13))
    self.ges_events = {
        TapBottle = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function BottleBoardWidget:getSize()
    return self.dimen
end

function BottleBoardWidget:drawPattern(bb, x, y, w, h, pattern_id)
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)

    local s1 = math.max(1, Screen:scaleBySize(1))
    local s2 = math.max(2, Screen:scaleBySize(2))
    local s3 = math.max(3, Screen:scaleBySize(3))
    local s4 = math.max(4, Screen:scaleBySize(4))
    local s6 = math.max(6, Screen:scaleBySize(6))
    local s8 = math.max(8, Screen:scaleBySize(8))

    if pattern_id == 1 then
        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_BLACK)

    elseif pattern_id == 2 then
        for py = y, y + h - 1, s4 do
            local band_h = math.min(s2, y + h - py)
            bb:paintRect(x, py, w, band_h, Blitbuffer.COLOR_BLACK)
        end

    elseif pattern_id == 3 then
        for px = x, x + w - 1, s4 do
            local band_w = math.min(s2, x + w - px)
            bb:paintRect(px, y, band_w, h, Blitbuffer.COLOR_BLACK)
        end

    elseif pattern_id == 4 then
        for py = y + s2, y + h - s3, s6 do
            for px = x + s2, x + w - s3, s6 do
                bb:paintRect(px, py, s3, s3, Blitbuffer.COLOR_BLACK)
            end
        end

    elseif pattern_id == 5 then
        local row = 0
        for py = y, y + h - 1, s4 do
            local col = 0
            local cell_h = math.min(s4, y + h - py)
            for px = x, x + w - 1, s4 do
                if (row + col) % 2 == 0 then
                    local cell_w = math.min(s4, x + w - px)
                    bb:paintRect(px, py, cell_w, cell_h, Blitbuffer.COLOR_BLACK)
                end
                col = col + 1
            end
            row = row + 1
        end

    elseif pattern_id == 6 then
        for py = y, y + h - 1, s2 do
            local dy = py - y
            for px = x, x + w - 1, s2 do
                local dx = px - x
                if ((dx + dy) % s8) < s3 then
                    bb:paintRect(px, py, math.min(s2, x + w - px), math.min(s2, y + h - py), Blitbuffer.COLOR_BLACK)
                end
            end
        end

    elseif pattern_id == 7 then
        for py = y, y + h - 1, s2 do
            local dy = py - y
            for px = x, x + w - 1, s2 do
                local dx = px - x
                if ((dx - dy + 1024 * s8) % s8) < s3 then
                    bb:paintRect(px, py, math.min(s2, x + w - px), math.min(s2, y + h - py), Blitbuffer.COLOR_BLACK)
                end
            end
        end

    elseif pattern_id == 8 then
        for py = y, y + h - 1, s6 do
            bb:paintRect(x, py, w, math.min(s1, y + h - py), Blitbuffer.COLOR_BLACK)
        end
        for px = x, x + w - 1, s6 do
            bb:paintRect(px, y, math.min(s1, x + w - px), h, Blitbuffer.COLOR_BLACK)
        end

    elseif pattern_id == 9 then
        local row = 0
        for py = y, y + h - 1, s6 do
            bb:paintRect(x, py, w, math.min(s1, y + h - py), Blitbuffer.COLOR_BLACK)
            local offset = (row % 2 == 1) and s4 or 0
            local row_h = math.min(s6, y + h - py)
            for px = x + offset, x + w - 1, s8 do
                bb:paintRect(px, py, math.min(s2, x + w - px), row_h, Blitbuffer.COLOR_BLACK)
            end
            row = row + 1
        end

    elseif pattern_id == 10 then
        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_GRAY_D)
        bb:paintBorder(x + s2, y + s2, math.max(2, w - 2 * s2), math.max(2, h - 2 * s2), s2, Blitbuffer.COLOR_BLACK)
        if w > 4 * s3 and h > 4 * s3 then
            bb:paintBorder(x + 2 * s3, y + 2 * s3, w - 4 * s3, h - 4 * s3, s1, Blitbuffer.COLOR_BLACK)
        end
    end

    -- Draw high-contrast centered badge pill
    local badge_text = PATTERNS[pattern_id] and PATTERNS[pattern_id].label or "?"
    local tsize = RenderText:sizeUtf8Text(0, w, self.label_face, badge_text, true, false)
    local bw = tsize.x + s6
    local bh = tsize.y_top + tsize.y_bottom + s2
    local bx = x + math.floor((w - bw) / 2)
    local by = y + math.floor((h - bh) / 2)

    bb:paintRect(bx, by, bw, bh, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(bx, by, bw, bh, s1, Blitbuffer.COLOR_BLACK)
    RenderText:renderUtf8Text(
        bb,
        bx + math.floor((bw - tsize.x) / 2),
        by + tsize.y_top + math.floor(s1 / 2),
        self.label_face,
        badge_text,
        true,
        false,
        Blitbuffer.COLOR_BLACK
    )

    bb:paintRect(x, y, w, s1, Blitbuffer.COLOR_BLACK)
end

function BottleBoardWidget:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)

    local bottles = self.game_dialog.bottles
    local num_bottles = #bottles
    if num_bottles == 0 then return end

    local rows = (num_bottles <= 6) and 1 or 2
    local cols = math.ceil(num_bottles / rows)

    local pad_x = Screen:scaleBySize(16)
    local pad_y = Screen:scaleBySize(20)
    local lift_offset = Screen:scaleBySize(16)

    local cell_w = math.floor((self.width - 2 * pad_x) / cols)
    local cell_h = math.floor((self.height - 2 * pad_y) / rows)

    local bottle_w = math.min(math.floor(cell_w * 0.72), Screen:scaleBySize(72))
    local bottle_h = math.min(math.floor(cell_h * 0.76), Screen:scaleBySize(210))
    local border_w = math.max(2, Screen:scaleBySize(3))
    local rim_overhang = Screen:scaleBySize(4)
    local rim_h = Screen:scaleBySize(5)

    local inner_w = bottle_w - 2 * border_w
    local inner_h = bottle_h - border_w
    local layer_h = math.floor(inner_h / CAPACITY)
    inner_h = layer_h * CAPACITY
    bottle_h = inner_h + border_w

    self.bottle_rects = {}

    for i = 1, num_bottles do
        local r = math.floor((i - 1) / cols)
        local c = (i - 1) % cols

        local cols_in_this_row = (r == rows - 1) and (num_bottles - r * cols) or cols
        local row_width = cols_in_this_row * cell_w
        local row_start_x = x + math.floor((self.width - row_width) / 2)

        local is_selected = (self.game_dialog.selected_bottle == i)
        local bx = row_start_x + c * cell_w + math.floor((cell_w - bottle_w) / 2)
        local by = y + pad_y + r * cell_h + math.floor((cell_h - bottle_h) / 2)
        if is_selected then
            by = by - lift_offset
        end

        self.bottle_rects[i] = Geom:new{
            x = bx - rim_overhang,
            y = by - lift_offset,
            w = bottle_w + 2 * rim_overhang,
            h = bottle_h + 2 * lift_offset,
        }

        if is_selected then
            local ind_w = math.floor(bottle_w * 0.5)
            local ind_h = Screen:scaleBySize(5)
            bb:paintRect(
                bx + math.floor((bottle_w - ind_w) / 2),
                by - Screen:scaleBySize(10),
                ind_w,
                ind_h,
                Blitbuffer.COLOR_BLACK
            )
        end

        local bottle = bottles[i]
        for layer = 1, #bottle do
            local pattern_id = bottle[layer]
            local lx = bx + border_w
            local ly = by + (CAPACITY - layer) * layer_h
            self:drawPattern(bb, lx, ly, inner_w, layer_h, pattern_id)
        end

        -- Bottle Rim, Walls, and Base
        bb:paintRect(bx - rim_overhang, by, bottle_w + 2 * rim_overhang, rim_h, Blitbuffer.COLOR_BLACK)
        bb:paintRect(bx, by, border_w, bottle_h, Blitbuffer.COLOR_BLACK)
        bb:paintRect(bx + bottle_w - border_w, by, border_w, bottle_h, Blitbuffer.COLOR_BLACK)
        bb:paintRect(bx, by + bottle_h - border_w, bottle_w, border_w * 2, Blitbuffer.COLOR_BLACK)

        -- Completed monochromatic indicator bar below bottle
        if #bottle == CAPACITY and bottle[1] == bottle[2] and bottle[2] == bottle[3] and bottle[3] == bottle[4] then
            bb:paintRect(
                bx + border_w,
                by + bottle_h + Screen:scaleBySize(6),
                inner_w,
                Screen:scaleBySize(3),
                Blitbuffer.COLOR_GRAY
            )
        end
    end
end

function BottleBoardWidget:onTapBottle(_, ges)
    if not ges or not ges.pos then return false end
    local gx, gy = ges.pos.x, ges.pos.y
    for i, rect in ipairs(self.bottle_rects) do
        if gx >= rect.x and gx <= (rect.x + rect.w) and gy >= rect.y and gy <= (rect.y + rect.h) then
            self.game_dialog:onBottleTapped(i)
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Fullscreen Game Dialog
--------------------------------------------------------------------------------
local WaterSortDialog = InputContainer:extend{
    plugin = nil,
}

function WaterSortDialog:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
    end

    self.level = self.plugin.level or 1
    self.bottles = self.plugin.bottles
    self.moves = self.plugin.moves or 0
    self.history = self.plugin.history or {}
    self.undos_left = (self.plugin.undos_left ~= nil) and self.plugin.undos_left or MAX_UNDOS
    self.extra_bottles_left = (self.plugin.extra_bottles_left ~= nil) and self.plugin.extra_bottles_left or MAX_EXTRA_BOTTLES
    self.selected_bottle = nil

    if not self.bottles or #self.bottles == 0 then
        self:loadLevel(self.level)
    else
        self:buildLayout()
        if not self:isSolved() and self:isDeadlocked() then
            UIManager:scheduleIn(0.1, function()
                self:showDeadlockDialog()
            end)
        end
    end
end

function WaterSortDialog:loadLevel(level_num)
    self.level = math.max(1, level_num)
    self.bottles = LevelGenerator.generate(self.level)
    self.moves = 0
    self.history = {}
    self.undos_left = MAX_UNDOS
    self.extra_bottles_left = MAX_EXTRA_BOTTLES
    self.selected_bottle = nil
    self:saveState()
    self:buildLayout()
    self:refreshScreen("full")
end

function WaterSortDialog:saveState()
    self.plugin:saveGameState(
        self.level,
        self.bottles,
        self.moves,
        self.history,
        self.undos_left,
        self.extra_bottles_left
    )
end

function WaterSortDialog:buildLayout()
    local title_bar = TitleBar:new{
        width = self.dimen.w,
        fullscreen = true,
        title = T(_("Water Sort • Level %1"), self.level),
        subtitle = T(
            _("Moves: %1  |  Undos: %2/%3  |  +Bottle: %4/%5"),
            self.moves,
            self.undos_left,
            MAX_UNDOS,
            self.extra_bottles_left,
            MAX_EXTRA_BOTTLES
        ),
        close_callback = function()
            self:onClose()
        end,
    }

    local btn_pad = Screen:scaleBySize(6)
    local btn_width = math.floor((self.dimen.w - Screen:scaleBySize(64)) / 5)

    local undo_btn = Button:new{
        text = T(_("Undo (%1)"), self.undos_left),
        width = btn_width,
        enabled = (#self.history > 0 and self.undos_left > 0),
        callback = function() self:undoMove() end,
    }
    local add_bottle_btn = Button:new{
        text = T(_("+Bottle (%1)"), self.extra_bottles_left),
        width = btn_width,
        enabled = (self.extra_bottles_left > 0),
        callback = function() self:addExtraBottle() end,
    }
    local restart_btn = Button:new{
        text = _("Restart"),
        width = btn_width,
        callback = function() self:loadLevel(self.level) end,
    }
    local jump_btn = Button:new{
        text = _("Level…"),
        width = btn_width,
        callback = function() self:promptLevelSelect() end,
    }
    local next_btn = Button:new{
        text = _("Skip »"),
        width = btn_width,
        callback = function() self:loadLevel(self.level + 1) end,
    }

    local controls_bar = FrameContainer:new{
        bordersize = 0,
        padding = btn_pad,
        CenterContainer:new{
            dimen = Geom:new{ w = self.dimen.w, h = undo_btn:getSize().h + 2 * btn_pad },
            HorizontalGroup:new{
                undo_btn,
                HorizontalSpan:new{ width = btn_pad },
                add_bottle_btn,
                HorizontalSpan:new{ width = btn_pad },
                restart_btn,
                HorizontalSpan:new{ width = btn_pad },
                jump_btn,
                HorizontalSpan:new{ width = btn_pad },
                next_btn,
            },
        },
    }

    local board_h = self.dimen.h - title_bar:getSize().h - controls_bar:getSize().h
    self.board_widget = BottleBoardWidget:new{
        game_dialog = self,
        width = self.dimen.w,
        height = board_h,
    }

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        VerticalGroup:new{
            title_bar,
            self.board_widget,
            controls_bar,
        },
    }
end

function WaterSortDialog:canPour(from_idx, to_idx)
    if from_idx == to_idx then return false end
    local src = self.bottles[from_idx]
    local dst = self.bottles[to_idx]
    if not src or not dst then return false end
    if #src == 0 or #dst >= CAPACITY then return false end
    if #dst == 0 then return true end
    return src[#src] == dst[#dst]
end

function WaterSortDialog:executePour(from_idx, to_idx)
    local src = self.bottles[from_idx]
    local dst = self.bottles[to_idx]
    local top_pattern = src[#src]
    local poured_count = 0

    while #src > 0 and src[#src] == top_pattern and #dst < CAPACITY do
        table.insert(dst, table.remove(src))
        poured_count = poured_count + 1
    end

    if poured_count > 0 then
        table.insert(self.history, {
            from = from_idx,
            to = to_idx,
            count = poured_count,
        })
        self.moves = self.moves + 1
        self:saveState()
    end
end

function WaterSortDialog:undoMove()
    if #self.history == 0 or self.undos_left <= 0 then return end
    local last = table.remove(self.history)
    if not last then return end

    local src = self.bottles[last.from]
    local dst = self.bottles[last.to]
    for _ = 1, last.count do
        table.insert(src, table.remove(dst))
    end

    self.undos_left = math.max(0, self.undos_left - 1)
    self.moves = math.max(0, self.moves - 1)
    self.selected_bottle = nil
    self:saveState()
    self:buildLayout()
    self:refreshScreen("ui")
end

function WaterSortDialog:addExtraBottle()
    if self.extra_bottles_left <= 0 then return end
    self.extra_bottles_left = self.extra_bottles_left - 1
    table.insert(self.bottles, {})
    self.selected_bottle = nil
    self:saveState()
    self:buildLayout()
    self:refreshScreen("ui")
end

function WaterSortDialog:isSolved()
    for _, bottle in ipairs(self.bottles) do
        if #bottle > 0 then
            if #bottle < CAPACITY then return false end
            local p = bottle[1]
            for i = 2, CAPACITY do
                if bottle[i] ~= p then return false end
            end
        end
    end
    return true
end

-- Helper: count how many contiguous matching units sit at the top of a bottle
function WaterSortDialog:getTopRun(bottle)
    if #bottle == 0 then return 0, nil end
    local top_p = bottle[#bottle]
    local run = 0
    for i = #bottle, 1, -1 do
        if bottle[i] == top_p then
            run = run + 1
        else
            break
        end
    end
    return run, top_p
end

-- Detects both strict deadlocks (no valid pours) and loop deadlocks (no bottle can clear its top layer)
function WaterSortDialog:isDeadlocked()
    if self:isSolved() then return false end

    -- 1. If any empty bottle exists and the level isn't solved, a productive move is always possible
    for _, bottle in ipairs(self.bottles) do
        if #bottle == 0 then
            return false
        end
    end

    -- 2. Sum available free slots per top pattern across all bottles
    local free_by_pattern = {}
    for _, bottle in ipairs(self.bottles) do
        local top_p = bottle[#bottle]
        local free_space = CAPACITY - #bottle
        free_by_pattern[top_p] = (free_by_pattern[top_p] or 0) + free_space
    end

    -- 3. Check if at least one bottle can completely offload its contiguous top layer
    --    into other bottles with the same top pattern (exposing a new pattern or emptying the bottle)
    for _, bottle in ipairs(self.bottles) do
        local top_run, top_p = self:getTopRun(bottle)
        if top_run < CAPACITY then
            local free_here = CAPACITY - #bottle
            local other_free = (free_by_pattern[top_p] or 0) - free_here
            if other_free >= top_run then
                return false
            end
        end
    end

    return true
end

function WaterSortDialog:showDeadlockDialog()
    local dialog
    dialog = ButtonDialog:new{
        title = _(
            "Deadlock! No Moves Left\n\n"
            .. "There are no productive pours remaining.\n"
            .. "Choose an option to continue:"
        ),
        title_align = "center",
        buttons = {
            {
                {
                    text = T(_("Undo Move (%1/%2 left)"), self.undos_left, MAX_UNDOS),
                    enabled = (#self.history > 0 and self.undos_left > 0),
                    callback = function()
                        UIManager:close(dialog)
                        self:undoMove()
                        if not self:isSolved() and self:isDeadlocked() then
                            UIManager:scheduleIn(0.1, function()
                                self:showDeadlockDialog()
                            end)
                        end
                    end,
                },
            },
            {
                {
                    text = T(_("+1 Empty Bottle (%1/%2 left)"), self.extra_bottles_left, MAX_EXTRA_BOTTLES),
                    enabled = (self.extra_bottles_left > 0),
                    callback = function()
                        UIManager:close(dialog)
                        self:addExtraBottle()
                    end,
                },
            },
            {
                {
                    text = _("Restart Level"),
                    callback = function()
                        UIManager:close(dialog)
                        self:loadLevel(self.level)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function WaterSortDialog:onBottleTapped(idx)
    -- If the board is currently deadlocked and the user dismissed the popup to inspect the board,
    -- tapping any bottle brings the deadlock recovery popup right back.
    if not self:isSolved() and self:isDeadlocked() then
        self:showDeadlockDialog()
        return
    end

    if not self.selected_bottle then
        if #self.bottles[idx] > 0 then
            self.selected_bottle = idx
            self:refreshScreen("ui")
        end
        return
    end

    if self.selected_bottle == idx then
        self.selected_bottle = nil
        self:refreshScreen("ui")
        return
    end

    if self:canPour(self.selected_bottle, idx) then
        self:executePour(self.selected_bottle, idx)
        self.selected_bottle = nil
        self:buildLayout()
        self:refreshScreen("ui")

        if self:isSolved() then
            local finished_level = self.level
            local finished_moves = self.moves
            UIManager:show(InfoMessage:new{
                text = T(
                    _("Level %1 Solved in %2 moves!\n\nTap anywhere to start Level %3."),
                    finished_level,
                    finished_moves,
                    finished_level + 1
                ),
                dismiss_callback = function()
                    self:loadLevel(finished_level + 1)
                end,
            })
        elseif self:isDeadlocked() then
            self:showDeadlockDialog()
        end
    else
        if #self.bottles[idx] > 0 then
            self.selected_bottle = idx
        else
            self.selected_bottle = nil
        end
        self:refreshScreen("ui")
    end
end

function WaterSortDialog:promptLevelSelect()
    local dialog
    dialog = InputDialog:new{
        title = _("Jump to Level (1 to Unlimited)"),
        input = tostring(self.level),
        input_type = "number",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Go"),
                    is_enter_default = true,
                    callback = function()
                        local num = tonumber(dialog:getInputValue())
                        UIManager:close(dialog)
                        if num and num >= 1 then
                            self:loadLevel(math.floor(num))
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function WaterSortDialog:refreshScreen(mode)
    UIManager:setDirty(self, function()
        return mode or "ui", self.dimen
    end)
end

function WaterSortDialog:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end

--------------------------------------------------------------------------------
-- Main KOReader Plugin Registration
--------------------------------------------------------------------------------
local WaterSortPlugin = WidgetContainer:extend{
    name = "watersort",
    is_doc_only = false,
}

function WaterSortPlugin:init()
    self:loadGameState()
    self.ui.menu:registerToMainMenu(self)
end

function WaterSortPlugin:loadGameState()
    local saved = G_reader_settings:readSetting(SETTINGS_KEY)
    if type(saved) == "table" and saved.level then
        self.level = saved.level
        self.bottles = saved.bottles
        self.moves = saved.moves or 0
        self.history = saved.history or {}
        self.undos_left = (saved.undos_left ~= nil) and saved.undos_left or MAX_UNDOS
        self.extra_bottles_left = (saved.extra_bottles_left ~= nil) and saved.extra_bottles_left or MAX_EXTRA_BOTTLES
    else
        self.level = 1
        self.bottles = nil
        self.moves = 0
        self.history = {}
        self.undos_left = MAX_UNDOS
        self.extra_bottles_left = MAX_EXTRA_BOTTLES
    end
end

function WaterSortPlugin:saveGameState(level, bottles, moves, history, undos_left, extra_bottles_left)
    self.level = level
    self.bottles = bottles
    self.moves = moves
    self.history = history
    self.undos_left = undos_left
    self.extra_bottles_left = extra_bottles_left
    G_reader_settings:saveSetting(SETTINGS_KEY, {
        level = level,
        bottles = bottles,
        moves = moves,
        history = history,
        undos_left = undos_left,
        extra_bottles_left = extra_bottles_left,
    })
end

function WaterSortPlugin:addToMainMenu(menu_items)
    menu_items.watersort_puzzle = {
        text = _("Water Sort Puzzle"),
        sorting_hint = "tools",
        callback = function()
            self:showGame()
        end,
    }
end

function WaterSortPlugin:showGame()
    local dialog = WaterSortDialog:new{
        plugin = self,
    }
    UIManager:show(dialog)
end

return WaterSortPlugin
