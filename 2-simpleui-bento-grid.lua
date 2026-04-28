local original_require = require

-- Override standard require to patch specific KOReader modules as they load
_G.require = function(modname)

    -- =========================================================
    -- Appearance Plugin Compatibility Fix (Color Devices)
    -- =========================================================
    if modname == "appearance.koplugin/book/progress_bar_colors" then
        local loaded = original_require(modname)
        local pw_ok, ProgressWidget = pcall(original_require, "ui/widget/progresswidget")
        
        if pw_ok and ProgressWidget and type(ProgressWidget) == "table" and not ProgressWidget._bento_shield then
            
            -- Safely execute the original update method to prevent errors during method chaining
            if type(ProgressWidget.updateStyle) == "function" then
                local unsafe_update = ProgressWidget.updateStyle
                ProgressWidget.updateStyle = function(self, ...) 
                    local ok, res = pcall(unsafe_update, self, ...) 
                    if ok then return res end
                end
            end
            
            if type(ProgressWidget._setColors) == "function" then
                local unsafe_set = ProgressWidget._setColors
                ProgressWidget._setColors = function(self, ...) 
                    local ok, res = pcall(unsafe_set, self, ...) 
                    if ok then return res end
                end
            end
            ProgressWidget._bento_shield = true
        end
        return loaded

    -- =========================================================
    -- Bento Grid Layout Engine
    -- =========================================================
    elseif modname == "sui_homescreen" then
        local loaded = original_require(modname)
        
        -- Search through upvalues to find the HomescreenWidget class. 
        -- Doing it this way prevents conflicts with the Appearance plugin's background rendering.
        local function getUpValue(func, name)
            local i = 1
            while true do
                local n, v = debug.getupvalue(func, i)
                if not n then break end
                if n == name then return v end
                i = i + 1
            end
        end

        local HomescreenWidget = getUpValue(loaded.show, "HomescreenWidget")
        
        if HomescreenWidget and not loaded._bento_patched then

            -- 1. Inject the Bento Grid settings into the context menu of each module
            local Registry = original_require("desktop_modules/moduleregistry")
            if Registry and Registry.list and not Registry._bento_menu_patched then
                for _, mod in ipairs(Registry.list()) do
                    if type(mod.getMenuItems) == "function" and not mod._bento_menu_patched then
                        local orig_getMenuItems = mod.getMenuItems
                        
                        mod.getMenuItems = function(ctx_menu)
                            local items = orig_getMenuItems(ctx_menu)
                            if type(items) == "table" then
                                table.insert(items, {
                                    text_func = function()
                                        local cur_val = _G.G_reader_settings:readSetting("simpleui_bento_width_" .. mod.id) or 100
                                        return "Bento Grid Column Width (" .. cur_val .. "%)"
                                    end,
                                    keep_menu_open = true,
                                    separator = true,
                                    callback = function()
                                        local UIManager  = original_require("ui/uimanager")
                                        local SpinWidget = original_require("ui/widget/spinwidget")
                                        local cur_val = _G.G_reader_settings:readSetting("simpleui_bento_width_" .. mod.id) or 100
                                        
                                        UIManager:show(SpinWidget:new{
                                            title_text    = "Bento Grid Column Width",
                                            info_text     = "Set the layout width for the Bento Grid.\n(e.g., 50 = 50% width, 100 = full row)",
                                            value         = cur_val,
                                            value_min     = 20,
                                            value_max     = 100,
                                            value_step    = 5,
                                            unit          = "%",
                                            ok_text       = "Apply",
                                            cancel_text   = "Cancel",
                                            default_value = 100,
                                            callback      = function(spin)
                                                _G.G_reader_settings:saveSetting("simpleui_bento_width_" .. mod.id, spin.value)
                                                if ctx_menu.refresh then ctx_menu.refresh() end
                                            end,
                                        })
                                    end,
                                })
                            end
                            return items
                        end
                        mod._bento_menu_patched = true
                    end
                end
                Registry._bento_menu_patched = true
            end

            -- 2. Patch the page update and render hooks directly on the prototype
            local orig_updatePage = HomescreenWidget._updatePage

            HomescreenWidget._updatePage = function(self, keep_cache, books_only)
                local Screen = original_require("device").screen
                if Screen:getWidth() > Screen:getHeight() then return orig_updatePage(self, keep_cache, books_only) end

                _G.BENTO_MOD_SCALES = _G.BENTO_MOD_SCALES or {}
                local gap = 15
                local inner_w = self._layout_inner_w or (Screen:getWidth() - 40)
                
                local modules_built = 0
                local orig_builds = {}
                local modules = Registry.list and Registry.list() or {}
                
                if _G.G_reader_settings then
                    for _, mod in ipairs(modules) do
                        local w_val = _G.G_reader_settings:readSetting("simpleui_bento_width_" .. mod.id)
                        _G.BENTO_MOD_SCALES[mod.id] = w_val and (w_val / 100.0) or 1.0
                    end
                end
                
                for _, mod in ipairs(modules) do
                    if type(mod.build) == "function" then
                        local m_id = mod.id
                        local m_orig = mod.build
                        orig_builds[m_id] = m_orig
                        
                        mod.build = function(w, ctx)
                            _G.BENTO_ACTIVE_MOD_ID = m_id
                            local pct = _G.BENTO_MOD_SCALES[m_id] or 1.0
                            local bw = (pct < 1.0) and math.floor((w * pct) - (gap / 2)) - 2 or w
                            return m_orig(bw, ctx)
                        end
                    end
                end

                local orig_makeModWrapper = self._makeModWrapper
                self._makeModWrapper = function(this, mod, widget, w)
                    modules_built = modules_built + 1
                    local m_id = mod.id or _G.BENTO_ACTIVE_MOD_ID
                    local pct = _G.BENTO_MOD_SCALES[m_id] or 1.0
                    local bw = (pct < 1.0) and math.floor((w * pct) - (gap / 2)) - 2 or w
                    
                    local wrapped = orig_makeModWrapper(this, mod, widget, bw)
                    if wrapped and type(wrapped) == "table" then
                        wrapped._bento_mod_id = m_id
                        wrapped._bento_bw = bw
                        
                        -- Update the internal dimension table so touch hitboxes and long-press highlights match the scaled width
                        if wrapped.dimen then wrapped.dimen.w = bw end
                    end
                    return wrapped
                end

                local ok, err = pcall(orig_updatePage, self, keep_cache, books_only)

                for _, mod in ipairs(modules) do
                    if orig_builds[mod.id] then mod.build = orig_builds[mod.id] end
                end
                self._makeModWrapper = orig_makeModWrapper

                if not ok then return end
                if modules_built == 0 then return end

                local FrameContainer = original_require("ui/widget/container/framecontainer")
                local TextWidget = original_require("ui/widget/textwidget")
                local ui_pad = 20
                pcall(function() ui_pad = original_require("sui_core").PAD * 2 end)

                local children = {}
                for i = 1, #self._body do
                    children[i] = self._body[i]
                    self._body[i] = nil
                end

                local chunks = {}
                local pre_build_widgets = {}
                local post_build_widgets = {}
                local pending_untagged = {}

                for i, w in ipairs(children) do
                    if type(w) == "table" and w._bento_mod_id then
                        local chunk = { mod_id = w._bento_mod_id, widgets = {} }
                        for _, uw in ipairs(pending_untagged) do table.insert(chunk.widgets, uw) end
                        pending_untagged = {}
                        table.insert(chunk.widgets, w)
                        table.insert(chunks, chunk)
                    else
                        if #chunks == 0 and i == 1 then
                            table.insert(pre_build_widgets, w)
                        else
                            table.insert(pending_untagged, w)
                        end
                    end
                end
                for _, uw in ipairs(pending_untagged) do table.insert(post_build_widgets, uw) end

                for _, w in ipairs(pre_build_widgets) do self._body[#self._body + 1] = w end
                
                local HorizontalGroup = original_require("ui/widget/horizontalgroup")
                local VerticalGroup = original_require("ui/widget/verticalgroup")
                local HorizontalSpan = original_require("ui/widget/horizontalspan")

                local current_row_cols = {}
                local current_row_width = 0

                local function flush_row()
                    if #current_row_cols == 0 then return end
                    
                    -- Make the row container transparent so the homescreen background remains visible
                    local h_group = HorizontalGroup:new{ align = "top", background = nil }
                    for i, col in ipairs(current_row_cols) do
                        
                        -- Make the column container transparent
                        local v_group = VerticalGroup:new{ align = "left", background = nil }
                        for _, chunk in ipairs(col.chunks) do
                            for _, w in ipairs(chunk.widgets) do
                                
                                local pct = _G.BENTO_MOD_SCALES[chunk.mod_id] or 1.0
                                if pct < 1.0 and type(w) == "table" and w.is_a and w:is_a(FrameContainer) and w[1] and w[1].is_a and w[1]:is_a(TextWidget) then
                                    local bw = w._bento_bw or (math.floor((inner_w * pct) - (gap / 2)) - 2)
                                    w.width = bw
                                    w[1].width = bw - ui_pad
                                    w[1].max_width = bw - ui_pad 
                                end

                                v_group[#v_group + 1] = w 
                                
                                if type(w) == "table" and w._bento_mod_id == "clock" then 
                                    self._clock_body_ref = v_group
                                    self._clock_body_idx = #v_group 
                                end
                                if type(w) == "table" and w._bento_mod_id == "header" then 
                                    self._header_body_ref = v_group
                                    self._header_body_idx = #v_group 
                                end
                            end
                        end
                        h_group[#h_group + 1] = v_group
                        if i < #current_row_cols then h_group[#h_group + 1] = HorizontalSpan:new{ width = gap } end
                    end
                    self._body[#self._body + 1] = h_group
                    current_row_cols = {}
                    current_row_width = 0
                end

                for _, chunk in ipairs(chunks) do
                    local pct = _G.BENTO_MOD_SCALES[chunk.mod_id] or 1.0
                    
                    if pct >= 1.0 then
                        flush_row()
                        for _, w in ipairs(chunk.widgets) do 
                            self._body[#self._body + 1] = w 
                            if type(w) == "table" and w._bento_mod_id == "clock" then 
                                self._clock_body_ref = self._body
                                self._clock_body_idx = #self._body 
                            end
                            if type(w) == "table" and w._bento_mod_id == "header" then 
                                self._header_body_ref = self._body
                                self._header_body_idx = #self._body 
                            end
                        end
                    else
                        if current_row_width + pct <= 1.01 then
                            table.insert(current_row_cols, { width = pct, chunks = { chunk } })
                            current_row_width = current_row_width + pct
                        else
                            local stacked = false
                            for _, col in ipairs(current_row_cols) do
                                if math.abs(col.width - pct) < 0.01 then
                                    table.insert(col.chunks, chunk)
                                    stacked = true
                                    break
                                end
                            end
                            
                            if not stacked then
                                flush_row()
                                table.insert(current_row_cols, { width = pct, chunks = { chunk } })
                                current_row_width = pct
                            end
                        end
                    end
                end
                
                flush_row()
                for _, w in ipairs(post_build_widgets) do self._body[#self._body + 1] = w end
            end

            loaded._bento_patched = true
        end
        return loaded
        
    else
        -- Fallback for all other modules
        return original_require(modname)
    end
end

return {}