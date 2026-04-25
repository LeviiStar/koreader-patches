local original_require = require

_G.require = function(modname)
    local loaded = original_require(modname)

    if modname == "sui_homescreen" and type(loaded) == "table" and loaded.show and not loaded._bento_patched then
        local orig_show = loaded.show

        -- 1. Master Registry Hook: Inject custom UI menus and read widths!
        local Registry = original_require("desktop_modules/moduleregistry")
        if Registry and not Registry._bento_patched then
            local function patch_mod(id, mod)
                if mod and type(mod) == "table" and not mod._bento_patched then
                    
                    -- Hook A: Modify the Render Build
                    if type(mod.build) == "function" then
                        local orig_build = mod.build
                        mod.build = function(w, ctx)
                            _G.BENTO_ACTIVE_MOD_ID = id
                            local pct = 1.0
                            if _G.G_reader_settings then
                                local w_val = _G.G_reader_settings:readSetting("simpleui_bento_width_" .. id)
                                if w_val then pct = w_val / 100.0 end
                            end
                            _G.BENTO_MOD_SCALES = _G.BENTO_MOD_SCALES or {}
                            _G.BENTO_MOD_SCALES[id] = pct
                            
                            local bw = (pct < 1.0) and math.floor((w * pct) - (15 / 2)) or w
                            return orig_build(bw, ctx)
                        end
                    end

                    -- Hook B: Inject our Custom Menu Item!
                    if type(mod.getMenuItems) == "function" then
                        local orig_getMenuItems = mod.getMenuItems
                        mod.getMenuItems = function(ctx_menu)
                            local items = orig_getMenuItems(ctx_menu)
                            if type(items) == "table" then
                                table.insert(items, {
                                    text = "Bento Grid Width",
                                    keep_menu_open = true,
                                    separator = true,
                                    callback = function()
                                        local UIManager  = original_require("ui/uimanager")
                                        local SpinWidget = original_require("ui/widget/spinwidget")
                                        local cur_val = _G.G_reader_settings:readSetting("simpleui_bento_width_" .. id) or 100
                                        
                                        UIManager:show(SpinWidget:new{
                                            title_text    = "Bento Grid Width",
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
                                                _G.G_reader_settings:saveSetting("simpleui_bento_width_" .. id, spin.value)
                                                if ctx_menu.refresh then ctx_menu.refresh() end
                                            end,
                                        })
                                    end,
                                })
                            end
                            return items
                        end
                    end

                    mod._bento_patched = true
                end
            end
            if Registry._modules then for id, mod in pairs(Registry._modules) do patch_mod(id, mod) end end
            local orig_get = Registry.get
            Registry.get = function(id) local mod = orig_get(id); patch_mod(id, mod); return mod end
            Registry._bento_patched = true
        end

        -- 2. Rendering Hook: The Masonry Auto-Slotting Engine
        loaded.show = function(...)
            orig_show(...)
            local inst = loaded._instance
            if not inst or inst._bento_patched then return end

            local orig_updatePage = inst._updatePage
            local orig_makeModWrapper = inst._makeModWrapper

            inst._updatePage = function(self, keep_cache, books_only)
                local Screen = original_require("device").screen
                if Screen:getWidth() > Screen:getHeight() then return orig_updatePage(self, keep_cache, books_only) end

                _G.BENTO_MOD_SCALES = _G.BENTO_MOD_SCALES or {}
                local gap = 15
                local inner_w = self._layout_inner_w or (Screen:getWidth() - 40)

                self._makeModWrapper = function(this, mod, widget, w)
                    local pct = _G.BENTO_MOD_SCALES[mod.id] or 1.0
                    local bw = (pct < 1.0) and math.floor((inner_w * pct) - (gap / 2)) or w
                    if widget.dimen then widget.dimen.w = bw end
                    return orig_makeModWrapper(this, mod, widget, bw)
                end

                _G.BENTO_ACTIVE_MOD_ID = "__pre_build__"
                local real_body = self._body
                local captured_items = {}
                local proxy_body = { clear = function() real_body:clear(); captured_items = {} end }
                setmetatable(proxy_body, { __newindex = function(t, k, v) table.insert(captured_items, { mod_id = _G.BENTO_ACTIVE_MOD_ID, widget = v }) end, __len = function() return #captured_items end })
                self._body = proxy_body

                local ok, err = pcall(orig_updatePage, self, keep_cache, books_only)
                self._body = real_body
                self._makeModWrapper = orig_makeModWrapper

                if not ok then return end

                local chunks = {}
                local current_chunk = nil
                local pre_build_widgets = {}
                local post_build_widgets = {}
                
                for i, item in ipairs(captured_items) do
                    local m_id = item.mod_id
                    local w = item.widget
                    if m_id == "__pre_build__" then table.insert(pre_build_widgets, w)
                    else
                        if i == #captured_items and w.is_a and w:is_a(original_require("ui/widget/container/centercontainer")) then table.insert(post_build_widgets, w)
                        else
                            if not current_chunk or current_chunk.mod_id ~= m_id then current_chunk = { mod_id = m_id, widgets = {} }; table.insert(chunks, current_chunk) end
                            local pct = _G.BENTO_MOD_SCALES[m_id] or 1.0
                            if pct < 1.0 and w.is_a and w:is_a(original_require("ui/widget/container/framecontainer")) and w[1] and w[1].is_a and w[1]:is_a(original_require("ui/widget/textwidget")) then
                                local bw = math.floor((inner_w * pct) - (gap / 2))
                                if w.dimen then w.dimen.w = bw end
                                local ui_pad = 20; pcall(function() ui_pad = original_require("sui_core").PAD * 2 end)
                                w[1].width = bw - ui_pad
                            end
                            table.insert(current_chunk.widgets, w)
                        end
                    end
                end

                for _, w in ipairs(pre_build_widgets) do real_body[#real_body + 1] = w end
                
                local HorizontalGroup = original_require("ui/widget/horizontalgroup")
                local VerticalGroup = original_require("ui/widget/verticalgroup")
                local HorizontalSpan = original_require("ui/widget/horizontalspan")

                local current_row_cols = {}
                local current_row_width = 0

                local function flush_row()
                    if #current_row_cols == 0 then return end
                    local h_group = HorizontalGroup:new{ align = "top" }
                    for i, col in ipairs(current_row_cols) do
                        local v_group = VerticalGroup:new{ align = "left" }
                        for _, chunk in ipairs(col.chunks) do
                            for _, w in ipairs(chunk.widgets) do 
                                v_group[#v_group + 1] = w 
                                if chunk.mod_id == "clock" then self._clock_body_ref = v_group; self._clock_body_idx = #v_group end
                                if chunk.mod_id == "header" then self._header_body_ref = v_group; self._header_body_idx = #v_group end
                            end
                        end
                        h_group[#h_group + 1] = v_group
                        if i < #current_row_cols then h_group[#h_group + 1] = HorizontalSpan:new{ width = gap } end
                    end
                    real_body[#real_body + 1] = h_group
                    current_row_cols = {}
                    current_row_width = 0
                end

                for _, chunk in ipairs(chunks) do
                    local pct = _G.BENTO_MOD_SCALES[chunk.mod_id] or 1.0
                    if pct >= 1.0 then
                        flush_row()
                        for _, w in ipairs(chunk.widgets) do 
                            real_body[#real_body + 1] = w 
                            if chunk.mod_id == "clock" then self._clock_body_ref = real_body; self._clock_body_idx = #real_body end
                            if chunk.mod_id == "header" then self._header_body_ref = real_body; self._header_body_idx = #real_body end
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

                for _, w in ipairs(post_build_widgets) do real_body[#real_body + 1] = w end
            end
            inst._bento_patched = true
        end
        loaded._bento_patched = true
    end
    return loaded
end

return {}