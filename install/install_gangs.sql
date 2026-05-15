CREATE TABLE IF NOT EXISTS `peak_gangs` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(80) NOT NULL,
    `leader` VARCHAR(60) NOT NULL COMMENT 'Player citizenid or framework identifier',
    `members` JSON NOT NULL COMMENT 'Array of { identifier, name, rank }',
    `metadata` JSON NOT NULL COMMENT 'Gang progression data: xp, crimeXp, tier, balance',
    `official_mark` JSON DEFAULT NULL COMMENT 'Serialized preset data for the gang official spray',
    `discovered_sprays` JSON DEFAULT NULL COMMENT 'Spray ids this gang has discovered on the turf map',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `idx_peak_gangs_name` (`name`),
    INDEX `idx_peak_gangs_leader` (`leader`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `spray_paintings`
    ADD COLUMN IF NOT EXISTS `gang_id` INT(11) DEFAULT NULL AFTER `player_name`,
    ADD COLUMN IF NOT EXISTS `status` ENUM('normal', 'contested') NOT NULL DEFAULT 'normal' AFTER `gang_id`,
    ADD COLUMN IF NOT EXISTS `contest_data` JSON DEFAULT NULL AFTER `status`,
    ADD INDEX IF NOT EXISTS `idx_spray_paintings_gang_status` (`gang_id`, `status`);

ALTER TABLE `peak_gangs`
    ADD COLUMN IF NOT EXISTS `discovered_sprays` JSON DEFAULT NULL AFTER `official_mark`;
