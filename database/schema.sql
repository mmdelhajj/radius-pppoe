-- ProRADIUS 4 - Complete Database Schema
-- ISP Billing and RADIUS Management System
-- MySQL/MariaDB Database
-- Generated from ProRADIUS4 production system analysis

CREATE DATABASE IF NOT EXISTS proradius4 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE proradius4;

-- ============================================================================
-- CORE CUSTOMER MANAGEMENT TABLES
-- ============================================================================

-- Customers (Main ISP subscribers)
CREATE TABLE `khclient` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(128) NOT NULL UNIQUE,
  `password` varchar(128) NOT NULL,
  `email` varchar(254) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `mobile` varchar(20) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `zip_code` varchar(20) DEFAULT NULL,
  `national_id` varchar(50) DEFAULT NULL,
  `balance` decimal(10,2) DEFAULT 0.00,
  `credit_limit` decimal(10,2) DEFAULT 0.00,
  `status` varchar(20) DEFAULT 'active',
  `service_id` int(11) DEFAULT NULL,
  `reseller_id` int(11) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `mac_address` varchar(17) DEFAULT NULL,
  `installation_date` datetime DEFAULT NULL,
  `expiry_date` datetime DEFAULT NULL,
  `auto_renew` tinyint(1) DEFAULT 1,
  `notes` text DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created_by` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_username` (`username`),
  KEY `idx_status` (`status`),
  KEY `idx_service_id` (`service_id`),
  KEY `idx_reseller_id` (`reseller_id`),
  KEY `idx_expiry_date` (`expiry_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Resellers (Multi-tenant support)
CREATE TABLE `khreseller` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(128) NOT NULL UNIQUE,
  `password` varchar(128) NOT NULL,
  `company_name` varchar(200) DEFAULT NULL,
  `email` varchar(254) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `balance` decimal(10,2) DEFAULT 0.00,
  `credit_limit` decimal(10,2) DEFAULT 0.00,
  `commission_rate` decimal(5,2) DEFAULT 0.00,
  `parent_reseller_id` int(11) DEFAULT NULL,
  `level` int(11) DEFAULT 1,
  `status` varchar(20) DEFAULT 'active',
  `permissions` text DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_username` (`username`),
  KEY `idx_parent_reseller_id` (`parent_reseller_id`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SERVICE & PACKAGE MANAGEMENT
-- ============================================================================

-- Service Packages/Plans
CREATE TABLE `servicequota` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(200) NOT NULL,
  `description` text DEFAULT NULL,
  `download_speed` int(11) DEFAULT NULL COMMENT 'kbps',
  `upload_speed` int(11) DEFAULT NULL COMMENT 'kbps',
  `burst_download` int(11) DEFAULT NULL COMMENT 'kbps',
  `burst_upload` int(11) DEFAULT NULL COMMENT 'kbps',
  `daily_quota` bigint(20) DEFAULT NULL COMMENT 'MB',
  `monthly_quota` bigint(20) DEFAULT NULL COMMENT 'MB',
  `price` decimal(10,2) DEFAULT 0.00,
  `validity_days` int(11) DEFAULT 30,
  `simultaneous_sessions` int(11) DEFAULT 1,
  `idle_timeout` int(11) DEFAULT NULL COMMENT 'seconds',
  `session_timeout` int(11) DEFAULT NULL COMMENT 'seconds',
  `priority` int(11) DEFAULT 5,
  `pool_name` varchar(128) DEFAULT NULL,
  `mikrotik_queue` varchar(128) DEFAULT NULL,
  `status` varchar(20) DEFAULT 'active',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_name` (`name`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- NAS/Router Devices
CREATE TABLE `khnas` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `nasname` varchar(128) NOT NULL UNIQUE,
  `shortname` varchar(32) DEFAULT NULL,
  `type` varchar(30) DEFAULT 'other',
  `ports` int(11) DEFAULT NULL,
  `secret` varchar(60) NOT NULL,
  `server` varchar(64) DEFAULT NULL,
  `community` varchar(50) DEFAULT NULL,
  `description` varchar(200) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `api_port` int(11) DEFAULT 8728,
  `api_username` varchar(64) DEFAULT NULL,
  `api_password` varchar(128) DEFAULT NULL,
  `status` varchar(20) DEFAULT 'active',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_nasname` (`nasname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- RADIUS ACCOUNTING TABLES (FreeRADIUS Standard)
-- ============================================================================

-- RADIUS Accounting Sessions
CREATE TABLE `khradacct` (
  `radacctid` bigint(21) NOT NULL AUTO_INCREMENT,
  `acctsessionid` varchar(64) NOT NULL,
  `acctuniqueid` varchar(32) NOT NULL,
  `username` varchar(64) NOT NULL,
  `realm` varchar(64) DEFAULT NULL,
  `nasipaddress` varchar(15) NOT NULL,
  `nasportid` varchar(50) DEFAULT NULL,
  `nasporttype` varchar(32) DEFAULT NULL,
  `acctstarttime` datetime DEFAULT NULL,
  `acctupdatetime` datetime DEFAULT NULL,
  `acctstoptime` datetime DEFAULT NULL,
  `acctinterval` int(12) DEFAULT NULL,
  `acctsessiontime` int(12) unsigned DEFAULT NULL,
  `acctauthentic` varchar(32) DEFAULT NULL,
  `connectinfo_start` varchar(50) DEFAULT NULL,
  `connectinfo_stop` varchar(50) DEFAULT NULL,
  `acctinputoctets` bigint(20) DEFAULT NULL,
  `acctoutputoctets` bigint(20) DEFAULT NULL,
  `calledstationid` varchar(50) DEFAULT NULL,
  `callingstationid` varchar(50) DEFAULT NULL,
  `acctterminatecause` varchar(32) DEFAULT NULL,
  `servicetype` varchar(32) DEFAULT NULL,
  `framedprotocol` varchar(32) DEFAULT NULL,
  `framedipaddress` varchar(15) DEFAULT NULL,
  `acctstartdelay` int(12) unsigned DEFAULT NULL,
  `acctstopdelay` int(12) unsigned DEFAULT NULL,
  `xascendsessionsvrkey` varchar(10) DEFAULT NULL,
  PRIMARY KEY (`radacctid`),
  UNIQUE KEY `acctuniqueid` (`acctuniqueid`),
  KEY `idx_username` (`username`),
  KEY `idx_framedipaddress` (`framedipaddress`),
  KEY `idx_acctsessionid` (`acctsessionid`),
  KEY `idx_acctsessiontime` (`acctsessiontime`),
  KEY `idx_acctstarttime` (`acctstarttime`),
  KEY `idx_acctstoptime` (`acctstoptime`),
  KEY `idx_nasipaddress` (`nasipaddress`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- RADIUS Authentication Check
CREATE TABLE `radcheck` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT '==',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- RADIUS Reply Attributes
CREATE TABLE `radreply` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT '=',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- RADIUS Group Check
CREATE TABLE `radgroupcheck` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `groupname` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT '==',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_groupname` (`groupname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- RADIUS Group Reply
CREATE TABLE `radgroupreply` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `groupname` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT '=',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_groupname` (`groupname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- RADIUS User Group Mapping
CREATE TABLE `radusergroup` (
  `username` varchar(64) NOT NULL DEFAULT '',
  `groupname` varchar(64) NOT NULL DEFAULT '',
  `priority` int(11) NOT NULL DEFAULT 1,
  KEY `idx_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- BILLING & FINANCIAL MANAGEMENT
-- ============================================================================

-- Transactions Log
CREATE TABLE `translog` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `trans_type` varchar(20) NOT NULL COMMENT 'payment,refund,credit,debit',
  `customer_id` int(11) DEFAULT NULL,
  `reseller_id` int(11) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `balance_before` decimal(10,2) DEFAULT 0.00,
  `balance_after` decimal(10,2) DEFAULT 0.00,
  `payment_method` varchar(50) DEFAULT NULL,
  `reference_no` varchar(100) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_customer_id` (`customer_id`),
  KEY `idx_reseller_id` (`reseller_id`),
  KEY `idx_trans_type` (`trans_type`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Invoices
CREATE TABLE `invoices` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `invoice_number` varchar(50) NOT NULL UNIQUE,
  `customer_id` int(11) NOT NULL,
  `reseller_id` int(11) DEFAULT NULL,
  `service_id` int(11) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `tax` decimal(10,2) DEFAULT 0.00,
  `discount` decimal(10,2) DEFAULT 0.00,
  `total_amount` decimal(10,2) NOT NULL,
  `status` varchar(20) DEFAULT 'unpaid',
  `due_date` date DEFAULT NULL,
  `paid_date` datetime DEFAULT NULL,
  `payment_method` varchar(50) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_invoice_number` (`invoice_number`),
  KEY `idx_customer_id` (`customer_id`),
  KEY `idx_status` (`status`),
  KEY `idx_due_date` (`due_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- IPTV MANAGEMENT
-- ============================================================================

-- IPTV Channels
CREATE TABLE `itv_channel` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(200) NOT NULL,
  `category` varchar(100) DEFAULT NULL,
  `logo_url` varchar(500) DEFAULT NULL,
  `stream_url` varchar(500) NOT NULL,
  `epg_id` varchar(100) DEFAULT NULL,
  `language` varchar(50) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `is_hd` tinyint(1) DEFAULT 0,
  `is_premium` tinyint(1) DEFAULT 0,
  `sort_order` int(11) DEFAULT 0,
  `status` varchar(20) DEFAULT 'active',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_category` (`category`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- IPTV Subscriptions
CREATE TABLE `itv_subscription` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `customer_id` int(11) NOT NULL,
  `package_id` int(11) DEFAULT NULL,
  `mac_address` varchar(17) DEFAULT NULL,
  `device_id` varchar(100) DEFAULT NULL,
  `start_date` datetime DEFAULT NULL,
  `expiry_date` datetime DEFAULT NULL,
  `status` varchar(20) DEFAULT 'active',
  `max_devices` int(11) DEFAULT 1,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_customer_id` (`customer_id`),
  KEY `idx_mac_address` (`mac_address`),
  KEY `idx_expiry_date` (`expiry_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SUPPORT TICKET SYSTEM
-- ============================================================================

-- Support Tickets
CREATE TABLE `tickets` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `ticket_number` varchar(50) NOT NULL UNIQUE,
  `customer_id` int(11) NOT NULL,
  `reseller_id` int(11) DEFAULT NULL,
  `category` varchar(100) DEFAULT NULL,
  `priority` varchar(20) DEFAULT 'medium',
  `subject` varchar(255) NOT NULL,
  `description` text NOT NULL,
  `status` varchar(20) DEFAULT 'open',
  `assigned_to` int(11) DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ticket_number` (`ticket_number`),
  KEY `idx_customer_id` (`customer_id`),
  KEY `idx_status` (`status`),
  KEY `idx_priority` (`priority`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ticket Replies
CREATE TABLE `ticket_replies` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `ticket_id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `message` text NOT NULL,
  `is_internal` tinyint(1) DEFAULT 0,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ticket_id` (`ticket_id`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- BANDWIDTH MANAGEMENT (FUP - Fair Usage Policy)
-- ============================================================================

-- Daily Quota Usage
CREATE TABLE `quota_daily` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `date` date NOT NULL,
  `input_octets` bigint(20) DEFAULT 0,
  `output_octets` bigint(20) DEFAULT 0,
  `total_octets` bigint(20) DEFAULT 0,
  `quota_limit` bigint(20) DEFAULT NULL,
  `is_exceeded` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_username_date` (`username`, `date`),
  KEY `idx_date` (`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Monthly Quota Usage
CREATE TABLE `quota_monthly` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `year` int(11) NOT NULL,
  `month` int(11) NOT NULL,
  `input_octets` bigint(20) DEFAULT 0,
  `output_octets` bigint(20) DEFAULT 0,
  `total_octets` bigint(20) DEFAULT 0,
  `quota_limit` bigint(20) DEFAULT NULL,
  `is_exceeded` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_username_yearmonth` (`username`, `year`, `month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- ONLINE USERS & SESSIONS
-- ============================================================================

-- Currently Online Users
CREATE TABLE `online_users` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL,
  `nasipaddress` varchar(15) NOT NULL,
  `acctsessionid` varchar(64) NOT NULL,
  `framedipaddress` varchar(15) DEFAULT NULL,
  `callingstationid` varchar(50) DEFAULT NULL,
  `acctstarttime` datetime DEFAULT NULL,
  `last_update` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_session` (`acctsessionid`),
  KEY `idx_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SYSTEM LOGS & NOTIFICATIONS
-- ============================================================================

-- System Activity Logs
CREATE TABLE `activity_log` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `user_type` varchar(20) DEFAULT NULL COMMENT 'admin,reseller,customer',
  `action` varchar(100) NOT NULL,
  `entity_type` varchar(50) DEFAULT NULL,
  `entity_id` int(11) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_action` (`action`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Notifications
CREATE TABLE `notifications` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `user_type` varchar(20) DEFAULT 'customer',
  `title` varchar(255) NOT NULL,
  `message` text NOT NULL,
  `type` varchar(50) DEFAULT 'info',
  `is_read` tinyint(1) DEFAULT 0,
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_is_read` (`is_read`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- DJANGO REQUIRED TABLES
-- ============================================================================

-- Django Sessions
CREATE TABLE `django_session` (
  `session_key` varchar(40) NOT NULL,
  `session_data` longtext NOT NULL,
  `expire_date` datetime NOT NULL,
  PRIMARY KEY (`session_key`),
  KEY `idx_expire_date` (`expire_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Django Migrations
CREATE TABLE `django_migrations` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `app` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `applied` datetime NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Django Content Types
CREATE TABLE `django_content_type` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `app_label` varchar(100) NOT NULL,
  `model` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `django_content_type_app_label_model` (`app_label`, `model`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Django Admin Log
CREATE TABLE `django_admin_log` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `action_time` datetime NOT NULL,
  `object_id` longtext DEFAULT NULL,
  `object_repr` varchar(200) NOT NULL,
  `action_flag` smallint(5) unsigned NOT NULL,
  `change_message` longtext NOT NULL,
  `content_type_id` int(11) DEFAULT NULL,
  `user_id` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_id` (`user_id`),
  KEY `idx_content_type_id` (`content_type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SYSTEM SETTINGS
-- ============================================================================

-- System Configuration
CREATE TABLE `system_settings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `setting_key` varchar(100) NOT NULL UNIQUE,
  `setting_value` text DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `group` varchar(50) DEFAULT 'general',
  `updated_at` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_setting_key` (`setting_key`),
  KEY `idx_group` (`group`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- INDEXES FOR PERFORMANCE OPTIMIZATION
-- ============================================================================

-- Additional composite indexes for common queries
ALTER TABLE `khradacct` ADD INDEX `idx_username_start_stop` (`username`, `acctstarttime`, `acctstoptime`);
ALTER TABLE `khclient` ADD INDEX `idx_reseller_status` (`reseller_id`, `status`);
ALTER TABLE `translog` ADD INDEX `idx_customer_date` (`customer_id`, `created_at`);
