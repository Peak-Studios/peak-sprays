ALTER TABLE `spray_paintings`
    ADD COLUMN `gang_id` VARCHAR(60) DEFAULT NULL COMMENT 'Optional territory/gang owner for gang spray integrations' AFTER `player_name`,
    ADD COLUMN `status` VARCHAR(20) NOT NULL DEFAULT 'normal' COMMENT 'Spray lifecycle/status marker' AFTER `gang_id`,
    ADD INDEX `idx_gang_id` (`gang_id`),
    ADD INDEX `idx_status` (`status`);
