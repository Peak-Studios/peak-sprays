CREATE TABLE IF NOT EXISTS `spray_paintings` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL COMMENT 'Player citizenid or framework identifier',
    `player_name` VARCHAR(100) DEFAULT 'Unknown',
    `corners` JSON NOT NULL COMMENT 'Four world-space canvas corners: topLeft, topRight, bottomLeft, bottomRight',
    `normal` JSON NOT NULL COMMENT 'World-space surface normal vector: x, y, z',
    `stroke_data` LONGTEXT NOT NULL COMMENT 'Serialized stroke history, including erase strokes',
    `canvas_width` INT(11) NOT NULL DEFAULT 1024,
    `canvas_height` INT(11) NOT NULL DEFAULT 1024,
    `world_x` FLOAT NOT NULL COMMENT 'Canvas center X coordinate used for nearby lookup',
    `world_y` FLOAT NOT NULL COMMENT 'Canvas center Y coordinate used for nearby lookup',
    `world_z` FLOAT NOT NULL COMMENT 'Canvas center Z coordinate used for nearby lookup',
    `stroke_count` INT(11) NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `expires_at` DATETIME DEFAULT NULL COMMENT 'NULL keeps the spray permanent; otherwise delete after this time',
    PRIMARY KEY (`id`),
    INDEX `idx_world_coords` (`world_x`, `world_y`, `world_z`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `peak_text_scenes` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL COMMENT 'Player citizenid or framework identifier',
    `player_name` VARCHAR(100) DEFAULT 'Unknown',
    `scene_type` VARCHAR(20) NOT NULL DEFAULT 'scene',
    `display_data` LONGTEXT NOT NULL COMMENT 'Serialized text scene display configuration',
    `coords` JSON NOT NULL COMMENT 'World-space scene position',
    `rotation` JSON DEFAULT NULL COMMENT 'Optional fixed marker rotation',
    `is_staff` TINYINT(1) NOT NULL DEFAULT 0,
    `deleted` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `expires_at` DATETIME DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_peak_text_scenes_identifier` (`identifier`),
    INDEX `idx_peak_text_scenes_deleted_expiry` (`deleted`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
