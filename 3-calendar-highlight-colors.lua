local original_require = require

_G.require = function(modname)
    local loaded = original_require(modname)

    -- =========================================================
    -- Universal Calendar Highlight Colors (Direct Inject Edition)
    -- =========================================================
    if modname == "statistics.koplugin/calendarview" and type(loaded) == "table" and not loaded._highlight_patched then
        
        -- 🎨 FALLBACK PALETTE
        -- Custom highlight colors used if Appearance plugin colors cannot be read.
        local FALLBACK_PALETTE = {
            "#FF0000", -- red
            "#FFA947", -- orange
            "#FFFF00", -- yellow
            "#88FF77", -- lime
            "#00AA66", -- forest
            "#00FFEE", -- cyan
            "#56A1FC", -- blue
            "#9500FF", -- purple
            "#FF00E6"  -- pink
        }

        local function parse_hex(hex_str)
            if type(hex_str) == "string" then
                return tonumber(hex_str:gsub("#", "0x"))
            elseif type(hex_str) == "number" then
                return hex_str
            end
            return nil
        end

        local function get_dynamic_palette()
            local palette = {}
            local bb_ok, BlitBuffer = pcall(original_require, "ffi/blitbuffer")
            
            -- Step 1: Attempt to pull custom colors from Appearance Plugin
            if bb_ok and BlitBuffer and type(BlitBuffer.HIGHLIGHT_COLORS) == "table" then
                local color_keys = {"red", "orange", "yellow", "lime", "forest", "cyan", "blue", "purple", "pink"}
                for _, key in ipairs(color_keys) do
                    local color_val = parse_hex(BlitBuffer.HIGHLIGHT_COLORS[key])
                    if color_val then table.insert(palette, color_val) end
                end
            end
            
            -- Step 2: If the Appearance plugin isn't used (or returned nothing), use the Fallback Palette
            if #palette == 0 then
                for _, hex_str in ipairs(FALLBACK_PALETTE) do
                    local color_val = parse_hex(hex_str)
                    if color_val then table.insert(palette, color_val) end
                end
            end
            
            if #palette == 0 then palette = { 0x8AE234 } end
            return palette
        end

        -- Hook the exact function that draws the calendar squares
        local orig_buildBookDayWidget = loaded.buildBookDayWidget
        if type(orig_buildBookDayWidget) == "function" then
            loaded.buildBookDayWidget = function(self, book, ...)
                local palette = self._custom_color_palette or get_dynamic_palette()
                self._custom_color_palette = palette
                
                -- PRE-INJECT the color into the calendar's memory right before it draws!
                if book and book.id_book and #palette > 0 then
                    self.book_colors = self.book_colors or {}
                    local num = tonumber(book.id_book) or 1
                    local color_index = (num % #palette) + 1
                    self.book_colors[book.id_book] = palette[color_index]
                end

                local widget = orig_buildBookDayWidget(self, book, ...)
                if widget and type(widget) == "table" then
                    widget._appearance_ignored = true -- Block Appearance plugin from flattening the colors
                end
                return widget
            end
        end
        loaded._highlight_patched = true
    end
    return loaded
end

return {}