-- Migration for Peak Sprays v1.0.0: Designs Library & Gang Templates
CREATE TABLE IF NOT EXISTS `peak_spray_designs` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL COMMENT 'Player citizenid or framework identifier',
    `player_name` VARCHAR(100) DEFAULT 'Unknown',
    `title` VARCHAR(100) NOT NULL DEFAULT 'Untitled Design',
    `category` VARCHAR(30) NOT NULL DEFAULT 'saved' COMMENT 'draft, saved, template, gang',
    `gang_id` VARCHAR(60) DEFAULT NULL COMMENT 'Associated gang identifier for gang designs',
    `variant` VARCHAR(50) DEFAULT 'default' COMMENT 'default, small, mural, territory_mark, monochrome',
    `composition` LONGTEXT NOT NULL COMMENT 'JSON serialized layered composition',
    `thumbnail` MEDIUMTEXT DEFAULT NULL COMMENT 'Base64 data URL thumbnail',
    `is_server_template` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 if official server-wide template',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_design_ident_cat` (`identifier`, `category`),
    INDEX `idx_design_gang` (`gang_id`),
    INDEX `idx_design_template` (`is_server_template`),
    INDEX `idx_design_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
