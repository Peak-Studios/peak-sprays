Locales = {}

local currentLocale = 'en'

local translations = {
    en = {
        ['spray_paint'] = 'Spray Paint',
        ['eraser'] = 'Eraser',
        ['select_first_corner'] = 'Aim at the wall and press LMB to place the first corner',
        ['select_second_corner'] = 'Aim at the wall and press LMB to place the second corner',
        ['selection_cancelled'] = 'Selection cancelled',
        ['area_too_small'] = 'Selected area is too small',
        ['area_too_large'] = 'Selected area is too large',
        ['invalid_surface'] = 'You cannot paint on this surface',
        ['surface_overflow'] = 'Selection extends beyond the wall surface',
        ['blacklisted_zone'] = 'Painting is not allowed in this area',
        ['painting_started'] = 'Spray painting mode active',
        ['painting_saved'] = 'Painting saved successfully',
        ['painting_cancelled'] = 'Painting cancelled',
        ['painting_auto_saved'] = 'Painting auto-saved (moved too far away)',
        ['max_strokes_reached'] = 'Maximum stroke limit reached',
        ['max_points_reached'] = 'Maximum detail limit reached, finish your stroke',
        ['undo_success'] = 'Undo',
        ['redo_success'] = 'Redo',
        ['nothing_to_undo'] = 'Nothing to undo',
        ['nothing_to_redo'] = 'Nothing to redo',
        ['no_item'] = 'You need a spray paint can',
        ['no_cloth'] = 'You need a cloth to erase',
        ['item_consumed'] = 'Spray paint consumed',
        ['cloth_consumed'] = 'Cloth consumed',
        ['eraser_started'] = 'Eraser mode active - aim at a painting to erase',
        ['eraser_saved'] = 'Erase saved successfully',
        ['eraser_cancelled'] = 'Erase cancelled',
        ['eraser_cleared_all'] = 'Entire painting cleared',
        ['no_painting_found'] = 'No painting found nearby',
        ['eraser_auto_saved'] = 'Erase auto-saved (moved too far away)',
        ['admin_no_permission'] = 'You do not have permission to do this',
        ['admin_panel_opened'] = 'Admin panel opened',
        ['admin_painting_deleted'] = 'Painting #%s deleted',
        ['admin_painting_not_found'] = 'Painting not found',
        ['admin_teleported'] = 'Teleported to painting #%s',
        ['scene_started'] = 'Scene editor opened',
        ['scene_saved'] = 'Scene saved successfully',
        ['scene_cancelled'] = 'Scene cancelled',
        ['scene_no_surface'] = 'Aim at a nearby surface first',
        ['scene_too_far'] = 'That surface is too far away',
        ['scene_invalid_text'] = 'Scene text cannot be empty',
        ['scene_text_too_long'] = 'Scene text is too long',
        ['scene_no_permission'] = 'You cannot create scenes here',
        ['scene_deleted'] = 'Scene deleted',
        ['scene_delete_denied'] = 'You cannot delete this scene',
        ['scene_not_found'] = 'No scene found nearby',
        ['scene_hidden_on'] = 'Text scenes hidden',
        ['scene_hidden_off'] = 'Text scenes visible',
        ['scene_place_help'] = '[ENTER] edit scene  [ESC] cancel',
        ['scene_editor_help'] = '[ENTER] edit position  [ESC] cancel',
        ['hud_size'] = 'SIZE',
        ['hud_pressure'] = 'PRESSURE',
        ['hud_mouse'] = 'MOUSE',
        ['hud_shake'] = 'SHAKE',
        ['hud_paint'] = 'PAINT',
        ['hud_erase'] = 'ERASE',
        ['hud_validate'] = 'VALIDATE',
        ['hud_cancel'] = 'CANCEL',
        ['hud_undo'] = 'UNDO',
        ['hud_redo'] = 'REDO',
        ['hud_settings'] = 'Settings',
        ['hud_color'] = 'COLOR',
        ['hud_brush'] = 'BRUSH',
        ['style_spray'] = 'Aerosol Spray',
        ['style_pen'] = 'Fine Marker',
        ['style_calligraphy'] = 'Calligraphy',
        ['style_splatter'] = 'Splatter Spray',
        ['style_airbrush'] = 'Soft Airbrush',
        ['style_drip'] = 'Drip Style',
        ['style_stencil'] = 'Stencil Stamp',
        ['log_paint_created'] = 'Painting Created',
        ['log_paint_created_desc'] = '**%s** (%s) created a new painting',
        ['log_paint_deleted'] = 'Painting Deleted',
        ['log_paint_deleted_desc'] = '**%s** (%s) deleted painting #%s',
        ['log_paint_erased'] = 'Painting Erased',
        ['log_paint_erased_desc'] = '**%s** (%s) erased part of painting #%s',
        ['log_admin_delete'] = 'Admin Delete',
        ['log_admin_delete_desc'] = 'Admin **%s** (%s) deleted painting #%s',
        ['log_field_location'] = 'Location',
        ['log_field_strokes'] = 'Strokes',
        ['log_field_area_size'] = 'Area Size',
        ['log_field_painting_id'] = 'Painting ID',
        ['log_field_creator'] = 'Original Creator',
    }
}

function Locales.Get(key, ...)
    local str = translations[currentLocale] and translations[currentLocale][key]
    if not str then
        str = translations['en'] and translations['en'][key]
    end
    if not str then
        return key
    end
    if ... then
        return string.format(str, ...)
    end
    return str
end

function Locales.SetLocale(locale)
    currentLocale = locale
end

function Locales.AddLocale(locale, strings)
    translations[locale] = strings
end

L = Locales.Get
