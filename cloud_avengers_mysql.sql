-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Feb 27, 2026 at 08:13 AM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.0.30

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `cloud_avengers`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `calc_cum_cr_gpa` (`mp_id` INTEGER, `s_id` INTEGER)   BEGIN
    UPDATE student_mp_stats
    SET cum_cr_weighted_factor = (case when cr_credits = '0' THEN '0' ELSE cr_weighted_factors/cr_credits END),
        cum_cr_unweighted_factor = (case when cr_credits = '0' THEN '0' ELSE cr_unweighted_factors/cr_credits END)
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `calc_cum_gpa` (`mp_id` INTEGER, `s_id` INTEGER)   BEGIN
    UPDATE student_mp_stats
    SET cum_weighted_factor = (case when gp_credits = '0' THEN '0' ELSE sum_weighted_factors/gp_credits END),
        cum_unweighted_factor = (case when gp_credits = '0' THEN '0' ELSE sum_unweighted_factors/gp_credits END)
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `calc_gpa_mp` (`s_id` INTEGER, `mp_id` INTEGER)   BEGIN
    DECLARE oldrec integer;

    SELECT count(*) INTO oldrec FROM student_mp_stats WHERE student_id = s_id and marking_period_id = mp_id;

    IF oldrec > 0 THEN
    UPDATE student_mp_stats sms
    JOIN (
        select
        student_id,
        marking_period_id,
        sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
        sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
        sum(credit_attempted) as gp_credits,
        sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
        sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
        sum( case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
        from student_report_card_grades
        where student_id = s_id
        and marking_period_id = mp_id
        and not gp_scale = 0
        and weighted_gp is not null
        group by student_id, marking_period_id
    ) as rcg
    ON rcg.student_id = sms.student_id and rcg.marking_period_id = sms.marking_period_id
    SET
        sms.sum_weighted_factors = rcg.sum_weighted_factors,
        sms.sum_unweighted_factors = rcg.sum_unweighted_factors,
        sms.cr_weighted_factors = rcg.cr_weighted,
        sms.cr_unweighted_factors = rcg.cr_unweighted,
        sms.gp_credits = rcg.gp_credits,
        sms.cr_credits = rcg.cr_credits;

    ELSE
    INSERT INTO student_mp_stats (student_id, marking_period_id, sum_weighted_factors, sum_unweighted_factors, grade_level_short, cr_weighted_factors, cr_unweighted_factors, gp_credits, cr_credits)
        select
            srcg.student_id,
            srcg.marking_period_id,
            sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
            sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
            (select eg.short_name
                from enroll_grade eg, marking_periods mp
                where eg.student_id = s_id
                and eg.syear = mp.syear
                and eg.school_id = mp.school_id
                and eg.start_date <= mp.end_date
                and mp.marking_period_id = mp_id
                order by eg.start_date desc
                limit 1) as short_name,
            sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
            sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
            sum(credit_attempted) as gp_credits,
            sum(case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
        from student_report_card_grades srcg
        where srcg.student_id = s_id
        and srcg.marking_period_id = mp_id
        and not srcg.gp_scale = 0
        and weighted_gp is not null
        group by srcg.student_id, srcg.marking_period_id, short_name;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `t_update_mp_stats` (`s_id` INTEGER, `mp_id` INTEGER)   BEGIN
    CALL calc_gpa_mp(s_id, mp_id);
    CALL calc_cum_gpa(mp_id, s_id);
    CALL calc_cum_cr_gpa(mp_id, s_id);
END$$

--
-- Functions
--
CREATE DEFINER=`root`@`localhost` FUNCTION `credit` (`cp_id` INTEGER, `mp_id` INTEGER) RETURNS DECIMAL(6,2)  BEGIN
    DECLARE course_detail_mp_id integer;
    DECLARE course_detail_mp varchar(3);
    DECLARE course_detail_credits numeric(6,2);
    DECLARE mp_detail_mp_id integer;
    DECLARE mp_detail_mp_type varchar(20);
    DECLARE val_mp_count integer;

    select marking_period_id,mp,credits into course_detail_mp_id,course_detail_mp,course_detail_credits from course_periods where course_period_id = cp_id;
    select marking_period_id,mp_type into mp_detail_mp_id,mp_detail_mp_type from marking_periods where marking_period_id = mp_id;

    IF course_detail_mp_id = mp_detail_mp_id THEN
        RETURN course_detail_credits;
    ELSEIF course_detail_mp = 'FY' AND mp_detail_mp_type = 'semester' THEN
        select count(*) into val_mp_count from marking_periods where parent_id = course_detail_mp_id group by parent_id;
    ELSEIF course_detail_mp = 'FY' and mp_detail_mp_type = 'quarter' THEN
        select count(*) into val_mp_count from marking_periods where grandparent_id = course_detail_mp_id group by grandparent_id;
    ELSEIF course_detail_mp = 'SEM' and mp_detail_mp_type = 'quarter' THEN
        select count(*) into val_mp_count from marking_periods where parent_id = course_detail_mp_id group by parent_id;
    ELSE
        RETURN course_detail_credits;
    END IF;

    IF val_mp_count > 0 THEN
        RETURN course_detail_credits/val_mp_count;
    ELSE
        RETURN course_detail_credits;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `set_class_rank_mp` (`mp_id` INTEGER) RETURNS INT(11)  BEGIN
    update student_mp_stats sms
    JOIN (
        select mp.marking_period_id, sgm.student_id,
        (select count(*)+1
            from student_mp_stats sgm3
            where sgm3.cum_cr_weighted_factor > sgm.cum_cr_weighted_factor
            and sgm3.marking_period_id = mp.marking_period_id
            and sgm3.student_id in (select distinct sgm2.student_id
                from student_mp_stats sgm2, student_enrollment se2
                where sgm2.student_id = se2.student_id
                and sgm2.marking_period_id = mp.marking_period_id
                and se2.grade_id = se.grade_id
                and se2.syear = se.syear)) as class_rank,
        (select count(*)
            from student_mp_stats sgm4
            where sgm4.marking_period_id = mp.marking_period_id
            and sgm4.student_id in (select distinct sgm5.student_id
                from student_mp_stats sgm5, student_enrollment se3
                where sgm5.student_id = se3.student_id
                and sgm5.marking_period_id = mp.marking_period_id
                and se3.grade_id = se.grade_id
                and se3.syear = se.syear)) as class_size
        from student_enrollment se, student_mp_stats sgm, marking_periods mp
        where se.student_id = sgm.student_id
        and sgm.marking_period_id = mp.marking_period_id
        and mp.marking_period_id = mp_id
        and se.syear = mp.syear
        and not sgm.cum_cr_weighted_factor is null
    ) as class_rank
    ON sms.marking_period_id = class_rank.marking_period_id and sms.student_id = class_rank.student_id
    set sms.cum_rank = class_rank.class_rank, sms.class_size = class_rank.class_size;
    RETURN 1;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `access_log`
--

CREATE TABLE `access_log` (
  `syear` decimal(4,0) NOT NULL,
  `username` varchar(100) DEFAULT NULL,
  `profile` varchar(30) DEFAULT NULL,
  `ip_address` varchar(50) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `status` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `access_log`
--

INSERT INTO `access_log` (`syear`, `username`, `profile`, `ip_address`, `user_agent`, `status`, `created_at`, `updated_at`) VALUES
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-07 09:35:51', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-07 09:36:01', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'Y', '2026-02-07 09:36:08', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:35:45', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:35:52', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:36:02', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:36:12', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:36:28', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:36:34', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:36:42', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:37:17', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-10 07:37:24', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'Y', '2026-02-10 07:37:32', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-12 07:36:24', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-12 07:36:36', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-12 07:36:45', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'F', '2026-02-12 07:36:49', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'Y', '2026-02-12 07:37:01', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36', 'Y', '2026-02-13 12:28:33', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'F', '2026-02-26 10:03:35', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'F', '2026-02-26 10:03:45', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'F', '2026-02-26 10:03:52', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'F', '2026-02-26 10:04:02', NULL),
(2025, 'admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'F', '2026-02-26 10:04:10', NULL),
(2025, 'Admin', NULL, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'F', '2026-02-26 10:04:17', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'Y', '2026-02-26 10:04:24', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'Y', '2026-02-27 06:10:20', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'Y', '2026-02-27 06:36:33', NULL),
(2025, 'admin', 'admin', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36', 'Y', '2026-02-27 06:42:41', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `accounting_categories`
--

CREATE TABLE `accounting_categories` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `short_name` varchar(10) DEFAULT NULL,
  `type` varchar(100) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_incomes`
--

CREATE TABLE `accounting_incomes` (
  `assigned_date` date DEFAULT NULL,
  `comments` text DEFAULT NULL,
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `category_id` int(11) DEFAULT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text DEFAULT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_payments`
--

CREATE TABLE `accounting_payments` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `staff_id` int(11) DEFAULT NULL,
  `title` text DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `amount` decimal(14,2) NOT NULL,
  `payment_date` date DEFAULT NULL,
  `comments` text DEFAULT NULL,
  `file_attached` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_salaries`
--

CREATE TABLE `accounting_salaries` (
  `staff_id` int(11) NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `comments` text DEFAULT NULL,
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text DEFAULT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `address`
--

CREATE TABLE `address` (
  `address_id` int(11) NOT NULL,
  `house_no` decimal(5,0) DEFAULT NULL,
  `direction` varchar(2) DEFAULT NULL,
  `street` varchar(30) DEFAULT NULL,
  `apt` varchar(5) DEFAULT NULL,
  `zipcode` varchar(10) DEFAULT NULL,
  `city` text DEFAULT NULL,
  `state` varchar(50) DEFAULT NULL,
  `mail_street` varchar(30) DEFAULT NULL,
  `mail_city` text DEFAULT NULL,
  `mail_state` varchar(50) DEFAULT NULL,
  `mail_zipcode` varchar(10) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `mail_address` text DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `address`
--

INSERT INTO `address` (`address_id`, `house_no`, `direction`, `street`, `apt`, `zipcode`, `city`, `state`, `mail_street`, `mail_city`, `mail_state`, `mail_zipcode`, `address`, `mail_address`, `phone`, `created_at`, `updated_at`) VALUES
(0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No Address', NULL, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `address_fields`
--

CREATE TABLE `address_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) DEFAULT NULL,
  `default_selection` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `address_field_categories`
--

CREATE TABLE `address_field_categories` (
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `residence` char(1) DEFAULT NULL,
  `mailing` char(1) DEFAULT NULL,
  `bus` char(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_calendar`
--

CREATE TABLE `attendance_calendar` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `minutes` int(11) DEFAULT NULL,
  `block` varchar(10) DEFAULT NULL,
  `calendar_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_calendars`
--

CREATE TABLE `attendance_calendars` (
  `school_id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `calendar_id` int(11) NOT NULL,
  `default_calendar` varchar(1) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `attendance_calendars`
--

INSERT INTO `attendance_calendars` (`school_id`, `title`, `syear`, `calendar_id`, `default_calendar`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, 'Main', 2025, 1, 'Y', NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `attendance_codes`
--

CREATE TABLE `attendance_codes` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `short_name` varchar(10) DEFAULT NULL,
  `type` varchar(10) DEFAULT NULL,
  `state_code` varchar(1) DEFAULT NULL,
  `default_code` varchar(1) DEFAULT NULL,
  `table_name` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `attendance_codes`
--

INSERT INTO `attendance_codes` (`id`, `syear`, `school_id`, `title`, `short_name`, `type`, `state_code`, `default_code`, `table_name`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 2025, 1, 'Absent', 'A', 'teacher', 'A', NULL, 0, NULL, '2026-02-07 09:25:50', NULL),
(2, 2025, 1, 'Present', 'P', 'teacher', 'P', 'Y', 0, NULL, '2026-02-07 09:25:50', NULL),
(3, 2025, 1, 'Tardy', 'T', 'teacher', 'P', NULL, 0, NULL, '2026-02-07 09:25:50', NULL),
(4, 2025, 1, 'Excused Absence', 'E', 'official', 'A', NULL, 0, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `attendance_code_categories`
--

CREATE TABLE `attendance_code_categories` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_completed`
--

CREATE TABLE `attendance_completed` (
  `staff_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `table_name` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_day`
--

CREATE TABLE `attendance_day` (
  `student_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `minutes_present` int(11) DEFAULT NULL,
  `state_value` decimal(2,1) DEFAULT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_period`
--

CREATE TABLE `attendance_period` (
  `student_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `attendance_code` int(11) DEFAULT NULL,
  `attendance_teacher_code` int(11) DEFAULT NULL,
  `attendance_reason` varchar(100) DEFAULT NULL,
  `admin` varchar(1) DEFAULT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `comment` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `billing_fees`
--

CREATE TABLE `billing_fees` (
  `student_id` int(11) NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `comments` text DEFAULT NULL,
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text DEFAULT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `waived_fee_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  `created_by` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `billing_payments`
--

CREATE TABLE `billing_payments` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `payment_date` date DEFAULT NULL,
  `comments` text DEFAULT NULL,
  `refunded_payment_id` int(11) DEFAULT NULL,
  `lunch_payment` varchar(1) DEFAULT NULL,
  `file_attached` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp(),
  `created_by` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `calendar_events`
--

CREATE TABLE `calendar_events` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `school_date` date DEFAULT NULL,
  `title` varchar(50) NOT NULL,
  `description` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `config`
--

CREATE TABLE `config` (
  `school_id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `config_value` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `config`
--

INSERT INTO `config` (`school_id`, `title`, `config_value`, `created_at`, `updated_at`) VALUES
(0, 'LOGIN', 'Yes', '2026-02-07 09:25:50', '2026-02-07 09:37:03'),
(0, 'VERSION', '12.7', '2026-02-07 09:25:50', NULL),
(0, 'TITLE', 'Cloud Avengers Student Information System', '2026-02-07 09:25:50', '2026-02-27 06:36:11'),
(0, 'NAME', 'Cloud Avengers Student Information System', '2026-02-07 09:25:50', '2026-02-27 06:34:06'),
(0, 'MODULES', 'a:13:{s:12:\"School_Setup\";b:1;s:8:\"Students\";b:1;s:5:\"Users\";b:1;s:10:\"Scheduling\";b:1;s:6:\"Grades\";b:1;s:10:\"Attendance\";b:1;s:11:\"Eligibility\";b:1;s:10:\"Discipline\";b:1;s:10:\"Accounting\";b:1;s:15:\"Student_Billing\";b:1;s:12:\"Food_Service\";b:1;s:9:\"Resources\";b:1;s:6:\"Custom\";b:1;}', '2026-02-07 09:25:50', NULL),
(0, 'PLUGINS', 'a:2:{s:23:\"Content_Security_Policy\";b:1;s:6:\"Moodle\";b:0;}', '2026-02-07 09:25:50', NULL),
(0, 'THEME', 'FlatSIS', '2026-02-07 09:25:50', NULL),
(0, 'THEME_FORCE', NULL, '2026-02-07 09:25:50', NULL),
(0, 'CREATE_USER_ACCOUNT', NULL, '2026-02-07 09:25:50', NULL),
(0, 'CREATE_STUDENT_ACCOUNT', NULL, '2026-02-07 09:25:50', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_AUTOMATIC_ACTIVATION', NULL, '2026-02-07 09:25:50', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_DEFAULT_SCHOOL', NULL, '2026-02-07 09:25:50', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_DEFAULT_SCHOOL_FORCE', NULL, '2026-02-07 09:25:50', NULL),
(0, 'STUDENTS_EMAIL_FIELD', NULL, '2026-02-07 09:25:50', NULL),
(0, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2026-02-07 09:25:50', NULL),
(1, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2026-02-07 09:25:50', NULL),
(0, 'LIMIT_EXISTING_CONTACTS_ADDRESSES', NULL, '2026-02-07 09:25:50', NULL),
(0, 'FAILED_LOGIN_LIMIT', '30', '2026-02-07 09:25:50', NULL),
(0, 'PASSWORD_STRENGTH', '2', '2026-02-07 09:25:50', NULL),
(0, 'FORCE_PASSWORD_CHANGE_ON_FIRST_LOGIN', NULL, '2026-02-07 09:25:50', NULL),
(0, 'GRADEBOOK_CONFIG_ADMIN_OVERRIDE', NULL, '2026-02-07 09:25:50', NULL),
(0, 'REMOVE_ACCESS_USERNAME_PREFIX_ADD', NULL, '2026-02-07 09:25:50', NULL),
(0, 'CONTENT_SECURITY_POLICY', 'script-src \'self\' \'unsafe-eval\' \'report-sample\'; style-src \'self\' \'unsafe-inline\'; connect-src \'self\'; form-action \'self\'; base-uri \'self\'; frame-ancestors \'none\'; object-src \'none\'; report-uri plugins/Content_Security_Policy/SaveReport.php', '2026-02-07 09:25:50', NULL),
(1, 'SCHOOL_SYEAR_OVER_2_YEARS', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'ATTENDANCE_FULL_DAY_MINUTES', '0', '2026-02-07 09:25:50', NULL),
(1, 'STUDENTS_USE_MAILING', NULL, '2026-02-07 09:25:50', NULL),
(1, 'CURRENCY', '$', '2026-02-07 09:25:50', NULL),
(1, 'DECIMAL_SEPARATOR', '.', '2026-02-07 09:25:50', NULL),
(1, 'THOUSANDS_SEPARATOR', ',', '2026-02-07 09:25:50', NULL),
(1, 'CLASS_RANK_CALCULATE_MPS', NULL, '2026-02-07 09:25:50', NULL),
(0, 'CONTENT_SECURITY_POLICY_CRON_DAY', '2026-02-27', '2026-02-07 09:26:08', '2026-02-27 06:10:22');

-- --------------------------------------------------------

--
-- Table structure for table `courses`
--

CREATE TABLE `courses` (
  `syear` decimal(4,0) NOT NULL,
  `course_id` int(11) NOT NULL,
  `subject_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `grade_level` int(11) DEFAULT NULL,
  `title` text NOT NULL COMMENT 'Title can be multilingual, use ParseMLField()',
  `short_name` varchar(25) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `credit_hours` decimal(6,2) DEFAULT NULL,
  `description` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `course_details`
-- (See below for the actual view)
--
CREATE TABLE `course_details` (
`school_id` int(11)
,`syear` decimal(4,0)
,`marking_period_id` int(11)
,`subject_id` int(11)
,`course_id` int(11)
,`course_period_id` int(11)
,`teacher_id` int(11)
,`course_title` text
,`cp_title` text
,`grade_scale_id` int(11)
,`mp` varchar(3)
,`credits` decimal(6,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `course_periods`
--

CREATE TABLE `course_periods` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `title` text DEFAULT NULL,
  `short_name` varchar(25) NOT NULL,
  `mp` varchar(3) DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `teacher_id` int(11) NOT NULL,
  `secondary_teacher_id` int(11) DEFAULT NULL,
  `room` varchar(10) DEFAULT NULL,
  `total_seats` decimal(10,0) DEFAULT NULL,
  `filled_seats` decimal(10,0) DEFAULT NULL,
  `does_attendance` text DEFAULT NULL,
  `does_honor_roll` varchar(1) DEFAULT NULL,
  `does_class_rank` varchar(1) DEFAULT NULL,
  `gender_restriction` varchar(1) DEFAULT NULL,
  `house_restriction` varchar(1) DEFAULT NULL,
  `availability` decimal(10,0) DEFAULT NULL,
  `parent_id` int(11) DEFAULT NULL,
  `calendar_id` int(11) DEFAULT NULL,
  `does_breakoff` varchar(1) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `grade_scale_id` int(11) DEFAULT NULL,
  `credits` decimal(6,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `course_period_school_periods`
--

CREATE TABLE `course_period_school_periods` (
  `course_period_school_periods_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `period_id` int(11) NOT NULL,
  `days` varchar(7) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `course_subjects`
--

CREATE TABLE `course_subjects` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `subject_id` int(11) NOT NULL,
  `title` text NOT NULL COMMENT 'Title can be multilingual, use ParseMLField()',
  `short_name` varchar(25) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `csp_reports`
--

CREATE TABLE `csp_reports` (
  `id` int(11) NOT NULL,
  `full_report` text NOT NULL,
  `violated_directive` text NOT NULL,
  `blocked_uri` text NOT NULL,
  `script_sample` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `custom_fields`
--

CREATE TABLE `custom_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) DEFAULT NULL,
  `default_selection` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `custom_fields`
--

INSERT INTO `custom_fields` (`id`, `type`, `title`, `sort_order`, `select_options`, `category_id`, `required`, `default_selection`, `created_at`, `updated_at`) VALUES
(200000000, 'select', 'Gender', 0, 'Male\nFemale', 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000001, 'select', 'Ethnicity', 1, 'White, Non-Hispanic\nBlack, Non-Hispanic\nAmer. Indian or Alaskan Native\nAsian or Pacific Islander\nHispanic\nOther', 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000002, 'text', 'Common Name', 2, NULL, 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000003, 'text', 'Social Security', 3, NULL, 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000004, 'date', 'Birthdate', 4, NULL, 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000005, 'select', 'Language', 5, 'English\nSpanish', 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000006, 'text', 'Physician', 6, NULL, 2, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000007, 'text', 'Physician Phone', 7, NULL, 2, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000008, 'text', 'Preferred Hospital', 8, NULL, 2, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000009, 'textarea', 'Comments', 9, NULL, 2, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000010, 'radio', 'Has Doctor\'s Note', 10, NULL, 2, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000011, 'textarea', 'Doctor\'s Note Comments', 11, NULL, 2, NULL, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_fields`
--

CREATE TABLE `discipline_fields` (
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `short_name` varchar(20) DEFAULT NULL,
  `data_type` varchar(30) NOT NULL,
  `column_name` text NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `discipline_fields`
--

INSERT INTO `discipline_fields` (`id`, `title`, `short_name`, `data_type`, `column_name`, `created_at`, `updated_at`) VALUES
(1, 'Violation', '', 'multiple_checkbox', 'CATEGORY_1', '2026-02-07 09:25:50', NULL),
(2, 'Detention Assigned', '', 'multiple_radio', 'CATEGORY_2', '2026-02-07 09:25:50', NULL),
(3, 'Parents Contacted By Teacher', '', 'checkbox', 'CATEGORY_3', '2026-02-07 09:25:50', NULL),
(4, 'Parent Contacted by Administrator', '', 'text', 'CATEGORY_4', '2026-02-07 09:25:50', NULL),
(5, 'Suspensions (Office Only)', '', 'multiple_checkbox', 'CATEGORY_5', '2026-02-07 09:25:50', NULL),
(6, 'Comments', '', 'textarea', 'CATEGORY_6', '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_field_usage`
--

CREATE TABLE `discipline_field_usage` (
  `id` int(11) NOT NULL,
  `discipline_field_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `select_options` text DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `discipline_field_usage`
--

INSERT INTO `discipline_field_usage` (`id`, `discipline_field_id`, `syear`, `school_id`, `title`, `select_options`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 3, 2025, 1, 'Parents Contacted by Teacher', '', 4, '2026-02-07 09:25:50', NULL),
(2, 4, 2025, 1, 'Parent Contacted by Administrator', '', 5, '2026-02-07 09:25:50', NULL),
(3, 6, 2025, 1, 'Comments', '', 6, '2026-02-07 09:25:50', NULL),
(4, 1, 2025, 1, 'Violation', 'Skipping Class\nProfanity, vulgarity, offensive language\nInsubordination (Refusal to Comply, Disrespectful Behavior)\nInebriated (Alcohol or Drugs)\nTalking out of Turn\nHarassment\nFighting\nPublic Display of Affection\nOther', 1, '2026-02-07 09:25:50', NULL),
(5, 2, 2025, 1, 'Detention Assigned', '10 Minutes\n20 Minutes\n30 Minutes\nDiscuss Suspension', 2, '2026-02-07 09:25:50', NULL),
(6, 5, 2025, 1, 'Suspensions (Office Only)', 'Half Day\nIn School Suspension\n1 Day\n2 Days\n3 Days\n5 Days\n7 Days\nExpulsion', 3, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_referrals`
--

CREATE TABLE `discipline_referrals` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `student_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `staff_id` int(11) DEFAULT NULL,
  `entry_date` date DEFAULT NULL,
  `referral_date` date DEFAULT NULL,
  `category_1` text DEFAULT NULL,
  `category_2` text DEFAULT NULL,
  `category_3` varchar(1) DEFAULT NULL,
  `category_4` text DEFAULT NULL,
  `category_5` text DEFAULT NULL,
  `category_6` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `eligibility`
--

CREATE TABLE `eligibility` (
  `student_id` int(11) NOT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `school_date` date DEFAULT NULL,
  `period_id` int(11) DEFAULT NULL,
  `eligibility_code` varchar(20) DEFAULT NULL,
  `course_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `eligibility_activities`
--

CREATE TABLE `eligibility_activities` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `eligibility_activities`
--

INSERT INTO `eligibility_activities` (`id`, `syear`, `school_id`, `title`, `start_date`, `end_date`, `comment`, `created_at`, `updated_at`) VALUES
(1, 2025, 1, 'Boy\'s Basketball', '2025-10-01', '2026-04-12', NULL, '2026-02-07 09:25:50', NULL),
(2, 2025, 1, 'Chess Team', '2025-09-03', '2026-06-05', NULL, '2026-02-07 09:25:50', NULL),
(3, 2025, 1, 'Girl\'s Basketball', '2025-10-01', '2026-04-12', NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `eligibility_completed`
--

CREATE TABLE `eligibility_completed` (
  `staff_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `enroll_grade`
-- (See below for the actual view)
--
CREATE TABLE `enroll_grade` (
`id` int(11)
,`syear` decimal(4,0)
,`school_id` int(11)
,`student_id` int(11)
,`start_date` date
,`end_date` date
,`short_name` varchar(3)
,`title` varchar(50)
);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_accounts`
--

CREATE TABLE `food_service_accounts` (
  `account_id` int(11) NOT NULL,
  `balance` decimal(9,2) NOT NULL,
  `transaction_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_accounts`
--

INSERT INTO `food_service_accounts` (`account_id`, `balance`, `transaction_id`, `created_at`, `updated_at`) VALUES
(1, 0.00, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_categories`
--

CREATE TABLE `food_service_categories` (
  `category_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `menu_id` int(11) NOT NULL,
  `title` varchar(25) NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_categories`
--

INSERT INTO `food_service_categories` (`category_id`, `school_id`, `menu_id`, `title`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 'Lunch Items', 1, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_items`
--

CREATE TABLE `food_service_items` (
  `item_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `short_name` varchar(25) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `description` varchar(25) DEFAULT NULL,
  `icon` varchar(50) DEFAULT NULL,
  `price` decimal(9,2) NOT NULL,
  `price_reduced` decimal(9,2) DEFAULT NULL,
  `price_free` decimal(9,2) DEFAULT NULL,
  `price_staff` decimal(9,2) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_items`
--

INSERT INTO `food_service_items` (`item_id`, `school_id`, `short_name`, `sort_order`, `description`, `icon`, `price`, `price_reduced`, `price_free`, `price_staff`, `created_at`, `updated_at`) VALUES
(1, 1, 'HOTL', 1, 'Student Lunch', 'Lunch.png', 1.65, 0.40, 0.00, 2.35, '2026-02-07 09:25:50', NULL),
(2, 1, 'MILK', 2, 'Milk', 'Milk.png', 0.25, NULL, NULL, 0.50, '2026-02-07 09:25:50', NULL),
(3, 1, 'XTRA', 3, 'Extra', 'Sandwich.png', 0.50, NULL, NULL, 1.00, '2026-02-07 09:25:50', NULL),
(4, 1, 'PIZZA', 4, 'Extra Pizza', 'Pizza.png', 1.00, NULL, NULL, 1.00, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_menus`
--

CREATE TABLE `food_service_menus` (
  `menu_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` varchar(25) NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_menus`
--

INSERT INTO `food_service_menus` (`menu_id`, `school_id`, `title`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 'Lunch', 1, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_menu_items`
--

CREATE TABLE `food_service_menu_items` (
  `menu_item_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `menu_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `category_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `does_count` varchar(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_menu_items`
--

INSERT INTO `food_service_menu_items` (`menu_item_id`, `school_id`, `menu_id`, `item_id`, `category_id`, `sort_order`, `does_count`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 1, 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(2, 1, 1, 2, 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(3, 1, 1, 3, 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(4, 1, 1, 4, 1, NULL, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_accounts`
--

CREATE TABLE `food_service_staff_accounts` (
  `staff_id` int(11) NOT NULL,
  `status` varchar(25) DEFAULT NULL,
  `barcode` varchar(50) DEFAULT NULL,
  `balance` decimal(9,2) NOT NULL,
  `transaction_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_transactions`
--

CREATE TABLE `food_service_staff_transactions` (
  `transaction_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `balance` decimal(9,2) DEFAULT NULL,
  `timestamp` datetime DEFAULT NULL,
  `short_name` varchar(25) DEFAULT NULL,
  `description` varchar(50) DEFAULT NULL,
  `seller_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_transaction_items`
--

CREATE TABLE `food_service_staff_transaction_items` (
  `item_id` int(11) NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `menu_item_id` int(11) DEFAULT NULL COMMENT 'References food_service_menu_items(menu_item_id)',
  `amount` decimal(9,2) DEFAULT NULL,
  `short_name` varchar(25) DEFAULT NULL,
  `description` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_student_accounts`
--

CREATE TABLE `food_service_student_accounts` (
  `student_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `discount` varchar(25) DEFAULT NULL,
  `status` varchar(25) DEFAULT NULL,
  `barcode` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_student_accounts`
--

INSERT INTO `food_service_student_accounts` (`student_id`, `account_id`, `discount`, `status`, `barcode`, `created_at`, `updated_at`) VALUES
(1, 1, NULL, NULL, '1000001', '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_transactions`
--

CREATE TABLE `food_service_transactions` (
  `transaction_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `student_id` int(11) DEFAULT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `discount` varchar(25) DEFAULT NULL,
  `balance` decimal(9,2) DEFAULT NULL,
  `timestamp` datetime DEFAULT NULL,
  `short_name` varchar(25) DEFAULT NULL,
  `description` varchar(50) DEFAULT NULL,
  `seller_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_transaction_items`
--

CREATE TABLE `food_service_transaction_items` (
  `item_id` int(11) NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `menu_item_id` int(11) DEFAULT NULL COMMENT 'References food_service_menu_items(menu_item_id)',
  `amount` decimal(9,2) DEFAULT NULL,
  `discount` varchar(25) DEFAULT NULL,
  `short_name` varchar(25) DEFAULT NULL,
  `description` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_assignments`
--

CREATE TABLE `gradebook_assignments` (
  `assignment_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `course_id` int(11) DEFAULT NULL,
  `assignment_type_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `points` int(11) NOT NULL,
  `description` longtext DEFAULT NULL,
  `file` text DEFAULT NULL,
  `default_points` int(11) DEFAULT NULL,
  `submission` varchar(1) DEFAULT NULL,
  `weight` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_assignment_types`
--

CREATE TABLE `gradebook_assignment_types` (
  `assignment_type_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `final_grade_percent` decimal(6,5) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `color` varchar(30) DEFAULT NULL,
  `created_mp` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_grades`
--

CREATE TABLE `gradebook_grades` (
  `student_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `assignment_id` int(11) NOT NULL,
  `points` decimal(6,2) DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `grades_completed`
--

CREATE TABLE `grades_completed` (
  `staff_id` int(11) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `history_marking_periods`
--

CREATE TABLE `history_marking_periods` (
  `parent_id` int(11) DEFAULT NULL,
  `mp_type` varchar(20) DEFAULT NULL,
  `name` varchar(50) NOT NULL,
  `short_name` varchar(10) DEFAULT NULL,
  `post_end_date` date DEFAULT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `lunch_period`
--

CREATE TABLE `lunch_period` (
  `student_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `attendance_code` int(11) DEFAULT NULL,
  `attendance_teacher_code` int(11) DEFAULT NULL,
  `attendance_reason` varchar(100) DEFAULT NULL,
  `admin` varchar(1) DEFAULT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `comment` varchar(100) DEFAULT NULL,
  `table_name` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `marking_periods`
-- (See below for the actual view)
--
CREATE TABLE `marking_periods` (
`marking_period_id` int(11)
,`mp_source` varchar(7)
,`syear` decimal(4,0)
,`school_id` int(11)
,`mp_type` varchar(20)
,`title` varchar(50)
,`short_name` varchar(10)
,`sort_order` decimal(10,0)
,`parent_id` int(11)
,`grandparent_id` int(11)
,`start_date` date
,`end_date` date
,`post_start_date` date
,`post_end_date` date
,`does_grades` varchar(1)
,`does_comments` varchar(1)
);

-- --------------------------------------------------------

--
-- Table structure for table `moodlexrosario`
--

CREATE TABLE `moodlexrosario` (
  `column` varchar(100) NOT NULL,
  `rosario_id` int(11) NOT NULL,
  `moodle_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `moodlexrosario`
--

INSERT INTO `moodlexrosario` (`column`, `rosario_id`, `moodle_id`, `created_at`, `updated_at`) VALUES
('staff_id', 1, 2, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `people`
--

CREATE TABLE `people` (
  `person_id` int(11) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `middle_name` varchar(50) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_fields`
--

CREATE TABLE `people_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) DEFAULT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) DEFAULT NULL,
  `default_selection` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_field_categories`
--

CREATE TABLE `people_field_categories` (
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `custody` char(1) DEFAULT NULL,
  `emergency` char(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_join_contacts`
--

CREATE TABLE `people_join_contacts` (
  `id` int(11) NOT NULL,
  `person_id` int(11) DEFAULT NULL,
  `title` varchar(100) DEFAULT NULL,
  `value` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_notes`
--

CREATE TABLE `portal_notes` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` text NOT NULL,
  `content` longtext DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `published_user` int(11) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `published_profiles` text DEFAULT NULL,
  `file_attached` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_polls`
--

CREATE TABLE `portal_polls` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` text NOT NULL,
  `votes_number` int(11) DEFAULT NULL,
  `display_votes` varchar(1) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `published_user` int(11) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `published_profiles` text DEFAULT NULL,
  `students_teacher_id` int(11) DEFAULT NULL,
  `excluded_users` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_poll_questions`
--

CREATE TABLE `portal_poll_questions` (
  `id` int(11) NOT NULL,
  `portal_poll_id` int(11) NOT NULL,
  `question` text NOT NULL,
  `type` varchar(20) DEFAULT NULL,
  `options` text DEFAULT NULL,
  `votes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `profile_exceptions`
--

CREATE TABLE `profile_exceptions` (
  `profile_id` int(11) NOT NULL,
  `modname` varchar(150) NOT NULL,
  `can_use` varchar(1) DEFAULT NULL,
  `can_edit` varchar(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `profile_exceptions`
--

INSERT INTO `profile_exceptions` (`profile_id`, `modname`, `can_use`, `can_edit`, `created_at`, `updated_at`) VALUES
(0, 'Attendance/DailySummary.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Attendance/StudentSummary.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Custom/Registration.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Eligibility/Student.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Eligibility/StudentList.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Food_Service/Accounts.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Food_Service/DailyMenus.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Food_Service/MenuItems.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Food_Service/Statements.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Grades/FinalGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Grades/GPARankList.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Grades/ProgressReports.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Grades/ReportCards.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Grades/StudentAssignments.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Grades/StudentGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Grades/Transcripts.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Resources/Resources.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Scheduling/Courses.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Scheduling/Requests.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Scheduling/Schedule.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'School_Setup/Calendar.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'School_Setup/Schools.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Student_Billing/DailyTransactions.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Student_Billing/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Student_Billing/StudentFees.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Student_Billing/StudentPayments.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Students/Student.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Students/Student.php&category_id=1', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Students/Student.php&category_id=3', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(0, 'Users/Preferences.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Categories.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/DailyTransactions.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Expenses.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Expenses.php&modfunc=remove', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Incomes.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Incomes.php&modfunc=remove', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Salaries.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Salaries.php&modfunc=remove', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/StaffBalances.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/StaffPayments.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/StaffPayments.php&modfunc=remove', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Accounting/Statements.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/AddAbsences.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/Administration.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/AttendanceCodes.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/DailySummary.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/DuplicateAttendance.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/FixDailyAttendance.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/Percent.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Attendance/TeacherCompletion.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Custom/AttendanceSummary.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Custom/CreateParents.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Custom/MyReport.php', NULL, NULL, '2026-02-07 09:25:50', NULL),
(1, 'Custom/NotifyParents.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Custom/Registration.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Custom/RemoveAccess.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/CategoryBreakdown.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/CategoryBreakdownTime.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/DisciplineForm.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/MakeReferral.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/ReferralForm.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/ReferralLog.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/Referrals.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Discipline/StudentFieldBreakdown.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Eligibility/Activities.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Eligibility/AddActivity.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Eligibility/EntryTimes.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Eligibility/Student.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Eligibility/StudentList.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Eligibility/TeacherCompletion.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/Accounts.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/ActivityReport.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/DailyMenus.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/Kiosk.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/MenuItems.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/MenuReports.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/Menus.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/Reminders.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/ServeMenus.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/Statements.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/Transactions.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Food_Service/TransactionsReport.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/Configuration.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/EditHistoryMarkingPeriods.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/EditReportCardGrades.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/FinalGrades.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/FixGPA.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/GPARankList.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/GradeBreakdown.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/HonorRoll.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/MassCreateAssignments.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/ProgressReports.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/ReportCardCommentCodes.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/ReportCardComments.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/ReportCardGrades.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/ReportCards.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/StudentGrades.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/TeacherCompletion.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Grades/Transcripts.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Resources/Resources.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/AddDrop.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/Courses.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/IncompleteSchedules.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/MassDrops.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/MassRequests.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/MassSchedule.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/PrintClassLists.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/PrintClassPictures.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/PrintRequests.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/PrintSchedules.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/Requests.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/RequestsReport.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/Schedule.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/Scheduler.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Scheduling/ScheduleReport.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/AccessLog.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/Calendar.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/Configuration.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/CopySchool.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/DatabaseBackup.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/GradeLevels.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/MarkingPeriods.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/Periods.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/PortalNotes.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/PortalPolls.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/Rollover.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/SchoolFields.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'School_Setup/Schools.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/DailyTransactions.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/Fees.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/MassAssignFees.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/MassAssignPayments.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/Statements.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/StudentBalances.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/StudentFees.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/StudentPayments.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Student_Billing/StudentPayments.php&modfunc=remove', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/AddDrop.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/AddUsers.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/AdvancedReport.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/AssignOtherInfo.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/EnrollmentCodes.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/Letters.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/PrintStudentInfo.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/Student.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/Student.php&category_id=1', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/Student.php&category_id=2', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/Student.php&category_id=3', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/Student.php&include=General_Info&student_id=new', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/StudentBreakdown.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/StudentFields.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Students/StudentLabels.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/AddStudents.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/Exceptions.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/Preferences.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/Profiles.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/TeacherPrograms.php&include=Attendance/TakeAttendance.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/TeacherPrograms.php&include=Eligibility/EnterEligibility.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/AnomalousGrades.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/Grades.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/InputFinalGrades.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/User.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/User.php&category_id=1', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/User.php&category_id=1&schools', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/User.php&category_id=1&user_profile', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/User.php&category_id=2', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/User.php&category_id=3', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/User.php&staff_id=new', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(1, 'Users/UserFields.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(2, 'Accounting/Salaries.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Accounting/StaffPayments.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Accounting/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Attendance/DailySummary.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Attendance/TakeAttendance.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Discipline/MakeReferral.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(2, 'Discipline/Referrals.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(2, 'Eligibility/EnterEligibility.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Food_Service/Accounts.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Food_Service/DailyMenus.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Food_Service/MenuItems.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Food_Service/Statements.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/AnomalousGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/Assignments-new.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/Assignments.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/Configuration.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/FinalGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/GradebookBreakdown.php', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(2, 'Grades/Grades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/InputFinalGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/ProgressReports.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/ReportCardCommentCodes.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/ReportCardComments.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/ReportCardGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/ReportCards.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Grades/StudentGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Resources/Resources.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Scheduling/Courses.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Scheduling/PrintClassLists.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Scheduling/Schedule.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'School_Setup/Calendar.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'School_Setup/Schools.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Students/AddUsers.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Students/AdvancedReport.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Students/Letters.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Students/Student.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Students/Student.php&category_id=1', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Students/Student.php&category_id=3', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Students/Student.php&category_id=4', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(2, 'Students/StudentLabels.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Users/Preferences.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Users/User.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Users/User.php&category_id=1', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Users/User.php&category_id=2', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 'Users/User.php&category_id=3', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Attendance/DailySummary.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Custom/Registration.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Eligibility/Student.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Eligibility/StudentList.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Food_Service/Accounts.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Food_Service/DailyMenus.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Food_Service/MenuItems.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Food_Service/Statements.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Grades/FinalGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Grades/GPARankList.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Grades/ProgressReports.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Grades/ReportCards.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Grades/StudentAssignments.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Grades/StudentGrades.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Grades/Transcripts.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Resources/Resources.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Scheduling/Courses.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Scheduling/Requests.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Scheduling/Schedule.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'School_Setup/Calendar.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'School_Setup/Schools.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Student_Billing/DailyTransactions.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Student_Billing/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Student_Billing/StudentFees.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Student_Billing/StudentPayments.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Students/Student.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Students/Student.php&category_id=1', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Students/Student.php&category_id=3', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Users/Preferences.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Users/User.php', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Users/User.php&category_id=1', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Users/User.php&category_id=2', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 'Users/User.php&category_id=3', 'Y', NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `program_config`
--

CREATE TABLE `program_config` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `program` varchar(100) NOT NULL,
  `title` varchar(100) NOT NULL,
  `value` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `program_config`
--

INSERT INTO `program_config` (`syear`, `school_id`, `program`, `title`, `value`, `created_at`, `updated_at`) VALUES
(2025, 1, 'eligibility', 'START_DAY', '1', '2026-02-07 09:25:50', NULL),
(2025, 1, 'eligibility', 'START_HOUR', '23', '2026-02-07 09:25:50', NULL),
(2025, 1, 'eligibility', 'START_MINUTE', '30', '2026-02-07 09:25:50', NULL),
(2025, 1, 'eligibility', 'START_M', 'PM', '2026-02-07 09:25:50', NULL),
(2025, 1, 'eligibility', 'END_DAY', '5', '2026-02-07 09:25:50', NULL),
(2025, 1, 'eligibility', 'END_HOUR', '23', '2026-02-07 09:25:50', NULL),
(2025, 1, 'eligibility', 'END_MINUTE', '30', '2026-02-07 09:25:50', NULL),
(2025, 1, 'eligibility', 'END_M', 'PM', '2026-02-07 09:25:50', NULL),
(2025, 1, 'attendance', 'ATTENDANCE_EDIT_DAYS_BEFORE', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'attendance', 'ATTENDANCE_EDIT_DAYS_AFTER', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'grades', 'GRADES_DOES_LETTER_PERCENT', '0', '2026-02-07 09:25:50', NULL),
(2025, 1, 'grades', 'GRADES_HIDE_NON_ATTENDANCE_COMMENT', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'grades', 'GRADES_TEACHER_ALLOW_EDIT', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'grades', 'GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT', 'Y', '2026-02-07 09:25:50', NULL),
(2025, 1, 'grades', 'GRADES_DO_STATS_STUDENTS_PARENTS', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'grades', 'GRADES_DO_STATS_ADMIN_TEACHERS', 'Y', '2026-02-07 09:25:50', NULL),
(2025, 1, 'students', 'STUDENTS_USE_BUS', 'Y', '2026-02-07 09:25:50', NULL),
(2025, 1, 'students', 'STUDENTS_USE_CONTACT', 'Y', '2026-02-07 09:25:50', NULL),
(2025, 1, 'students', 'STUDENTS_SEMESTER_COMMENTS', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'moodle', 'MOODLE_URL', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'moodle', 'MOODLE_TOKEN', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'moodle', 'MOODLE_PARENT_ROLE_ID', NULL, '2026-02-07 09:25:50', NULL),
(2025, 1, 'moodle', 'MOODLE_API_PROTOCOL', 'rest', '2026-02-07 09:25:50', NULL),
(2025, 1, 'food_service', 'FOOD_SERVICE_BALANCE_WARNING', '5', '2026-02-07 09:25:50', NULL),
(2025, 1, 'food_service', 'FOOD_SERVICE_BALANCE_MINIMUM', '-40', '2026-02-07 09:25:50', NULL),
(2025, 1, 'food_service', 'FOOD_SERVICE_BALANCE_TARGET', '19', '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `program_user_config`
--

CREATE TABLE `program_user_config` (
  `user_id` int(11) NOT NULL,
  `program` varchar(100) NOT NULL,
  `title` varchar(100) NOT NULL,
  `value` longtext DEFAULT NULL,
  `school_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comments`
--

CREATE TABLE `report_card_comments` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `course_id` int(11) DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `scale_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` text NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_comments`
--

INSERT INTO `report_card_comments` (`id`, `syear`, `school_id`, `course_id`, `category_id`, `scale_id`, `sort_order`, `title`, `created_at`, `updated_at`) VALUES
(1, 2025, 1, NULL, NULL, NULL, 1, '^n Fails to Meet Course Requirements', '2026-02-07 09:25:50', NULL),
(2, 2025, 1, NULL, NULL, NULL, 2, '^n Comes to ^s Class Unprepared', '2026-02-07 09:25:50', NULL),
(3, 2025, 1, NULL, NULL, NULL, 3, '^n Exerts Positive Influence in Class', '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_categories`
--

CREATE TABLE `report_card_comment_categories` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `course_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` text NOT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `color` varchar(30) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_codes`
--

CREATE TABLE `report_card_comment_codes` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `scale_id` int(11) NOT NULL,
  `title` varchar(5) NOT NULL,
  `short_name` varchar(100) DEFAULT NULL,
  `comment` varchar(100) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_code_scales`
--

CREATE TABLE `report_card_comment_code_scales` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` varchar(25) NOT NULL,
  `comment` varchar(100) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_grades`
--

CREATE TABLE `report_card_grades` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` varchar(5) NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `gpa_value` decimal(7,2) DEFAULT NULL,
  `break_off` decimal(7,2) DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `grade_scale_id` int(11) DEFAULT NULL,
  `unweighted_gp` decimal(7,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_grades`
--

INSERT INTO `report_card_grades` (`id`, `syear`, `school_id`, `title`, `sort_order`, `gpa_value`, `break_off`, `comment`, `grade_scale_id`, `unweighted_gp`, `created_at`, `updated_at`) VALUES
(1, 2025, 1, 'A+', 1, 4.00, 97.00, 'Consistently superior', 1, NULL, '2026-02-07 09:25:50', NULL),
(2, 2025, 1, 'A', 2, 4.00, 93.00, 'Superior', 1, NULL, '2026-02-07 09:25:50', NULL),
(3, 2025, 1, 'A-', 3, 3.75, 90.00, 'Superior', 1, NULL, '2026-02-07 09:25:50', NULL),
(4, 2025, 1, 'B+', 4, 3.50, 87.00, 'Above average', 1, NULL, '2026-02-07 09:25:50', NULL),
(5, 2025, 1, 'B', 5, 3.00, 83.00, 'Above average', 1, NULL, '2026-02-07 09:25:50', NULL),
(6, 2025, 1, 'B-', 6, 2.75, 80.00, 'Above average', 1, NULL, '2026-02-07 09:25:50', NULL),
(7, 2025, 1, 'C+', 7, 2.50, 77.00, 'Average', 1, NULL, '2026-02-07 09:25:50', NULL),
(8, 2025, 1, 'C', 8, 2.00, 73.00, 'Average', 1, NULL, '2026-02-07 09:25:50', NULL),
(9, 2025, 1, 'C-', 9, 1.75, 70.00, 'Average', 1, NULL, '2026-02-07 09:25:50', NULL),
(10, 2025, 1, 'D+', 10, 1.50, 67.00, 'Below average', 1, NULL, '2026-02-07 09:25:50', NULL),
(11, 2025, 1, 'D', 11, 1.00, 63.00, 'Below average', 1, NULL, '2026-02-07 09:25:50', NULL),
(12, 2025, 1, 'D-', 12, 0.75, 60.00, 'Below average', 1, NULL, '2026-02-07 09:25:50', NULL),
(13, 2025, 1, 'F', 13, 0.00, 0.00, 'Failing', 1, NULL, '2026-02-07 09:25:50', NULL),
(14, 2025, 1, 'I', 14, 0.00, 0.00, 'Incomplete', 1, NULL, '2026-02-07 09:25:50', NULL),
(15, 2025, 1, 'N/A', 15, NULL, NULL, NULL, 1, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `report_card_grade_scales`
--

CREATE TABLE `report_card_grade_scales` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `comment` text DEFAULT NULL,
  `hhr_gpa_value` decimal(7,2) DEFAULT NULL,
  `hr_gpa_value` decimal(7,2) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `gp_scale` decimal(7,2) NOT NULL,
  `gp_passing_value` decimal(7,2) NOT NULL,
  `hrs_gpa_value` decimal(7,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_grade_scales`
--

INSERT INTO `report_card_grade_scales` (`id`, `syear`, `school_id`, `title`, `comment`, `hhr_gpa_value`, `hr_gpa_value`, `sort_order`, `rollover_id`, `gp_scale`, `gp_passing_value`, `hrs_gpa_value`, `created_at`, `updated_at`) VALUES
(1, 2025, 1, 'Main', NULL, NULL, NULL, 1, NULL, 4.00, 0.00, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `resources`
--

CREATE TABLE `resources` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text NOT NULL,
  `link` text DEFAULT NULL,
  `published_profiles` text DEFAULT NULL,
  `published_grade_levels` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `resources`
--

INSERT INTO `resources` (`id`, `school_id`, `title`, `link`, `published_profiles`, `published_grade_levels`, `created_at`, `updated_at`) VALUES
(1, 1, 'Print Handbook', 'Help.php', NULL, NULL, '2026-02-07 09:25:50', NULL),
(2, 1, 'Quick Setup Guide', 'https://www.rosariosis.org/quick-setup-guide/', ',1,', NULL, '2026-02-07 09:25:50', NULL),
(3, 1, 'Forum', 'https://www.rosariosis.org/forum/', ',1,2,', NULL, '2026-02-07 09:25:50', NULL),
(4, 1, 'Contribute', 'https://www.rosariosis.org/contribute/', NULL, NULL, '2026-02-07 09:25:50', NULL),
(5, 1, 'Report a bug', 'https://gitlab.com/francoisjacquet/rosariosis/-/issues', NULL, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `schedule`
--

CREATE TABLE `schedule` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date DEFAULT NULL,
  `modified_by` varchar(255) DEFAULT NULL,
  `course_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `mp` varchar(3) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `scheduler_lock` varchar(1) DEFAULT NULL,
  `id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `schedule_requests`
--

CREATE TABLE `schedule_requests` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `request_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `subject_id` int(11) DEFAULT NULL,
  `course_id` int(11) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `priority` int(11) DEFAULT NULL,
  `with_teacher_id` int(11) DEFAULT NULL,
  `not_teacher_id` int(11) DEFAULT NULL,
  `with_period_id` int(11) DEFAULT NULL,
  `not_period_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `schools`
--

CREATE TABLE `schools` (
  `syear` decimal(4,0) NOT NULL,
  `id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `address` varchar(100) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `state` varchar(10) DEFAULT NULL,
  `zipcode` varchar(10) DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `principal` varchar(100) DEFAULT NULL,
  `www_address` text DEFAULT NULL,
  `school_number` varchar(50) DEFAULT NULL,
  `short_name` varchar(25) DEFAULT NULL,
  `reporting_gp_scale` decimal(10,3) DEFAULT NULL,
  `number_days_rotation` decimal(1,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `schools`
--

INSERT INTO `schools` (`syear`, `id`, `title`, `address`, `city`, `state`, `zipcode`, `phone`, `principal`, `www_address`, `school_number`, `short_name`, `reporting_gp_scale`, `number_days_rotation`, `created_at`, `updated_at`) VALUES
(2025, 1, 'Default School', '500 S. Street St.', 'Springfield', 'IL', '62704', NULL, 'Mr. Principal', 'www.rosariosis.org', NULL, NULL, 4.000, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `school_fields`
--

CREATE TABLE `school_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text DEFAULT NULL,
  `required` varchar(1) DEFAULT NULL,
  `default_selection` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `school_gradelevels`
--

CREATE TABLE `school_gradelevels` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `short_name` varchar(3) DEFAULT NULL,
  `title` varchar(50) NOT NULL,
  `next_grade_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_gradelevels`
--

INSERT INTO `school_gradelevels` (`id`, `school_id`, `short_name`, `title`, `next_grade_id`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 'KG', 'Kindergarten', 2, 1, '2026-02-07 09:25:50', NULL),
(2, 1, '01', '1st', 3, 2, '2026-02-07 09:25:50', NULL),
(3, 1, '02', '2nd', 4, 3, '2026-02-07 09:25:50', NULL),
(4, 1, '03', '3rd', 5, 4, '2026-02-07 09:25:50', NULL),
(5, 1, '04', '4th', 6, 5, '2026-02-07 09:25:50', NULL),
(6, 1, '05', '5th', 7, 6, '2026-02-07 09:25:50', NULL),
(7, 1, '06', '6th', 8, 7, '2026-02-07 09:25:50', NULL),
(8, 1, '07', '7th', 9, 8, '2026-02-07 09:25:50', NULL),
(9, 1, '08', '8th', NULL, 9, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `school_marking_periods`
--

CREATE TABLE `school_marking_periods` (
  `marking_period_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `mp` varchar(3) NOT NULL,
  `school_id` int(11) NOT NULL,
  `parent_id` int(11) DEFAULT NULL,
  `title` varchar(50) NOT NULL,
  `short_name` varchar(10) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `post_start_date` date DEFAULT NULL,
  `post_end_date` date DEFAULT NULL,
  `does_grades` varchar(1) DEFAULT NULL,
  `does_comments` varchar(1) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_marking_periods`
--

INSERT INTO `school_marking_periods` (`marking_period_id`, `syear`, `mp`, `school_id`, `parent_id`, `title`, `short_name`, `sort_order`, `start_date`, `end_date`, `post_start_date`, `post_end_date`, `does_grades`, `does_comments`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, 2025, 'FY', 1, NULL, 'Full Year', 'FY', 1, '2025-06-13', '2026-06-12', NULL, NULL, NULL, NULL, NULL, '2026-02-07 09:25:50', NULL),
(2, 2025, 'SEM', 1, 1, 'Semester 1', 'S1', 1, '2025-06-13', '2025-12-31', '2025-12-28', '2025-12-31', NULL, NULL, NULL, '2026-02-07 09:25:50', NULL),
(3, 2025, 'SEM', 1, 1, 'Semester 2', 'S2', 2, '2026-01-01', '2026-06-12', '2026-06-11', '2026-06-12', NULL, NULL, NULL, '2026-02-07 09:25:50', NULL),
(4, 2025, 'QTR', 1, 2, 'Quarter 1', 'Q1', 1, '2025-06-13', '2025-09-13', '2025-09-11', '2025-09-13', 'Y', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(5, 2025, 'QTR', 1, 2, 'Quarter 2', 'Q2', 2, '2025-09-14', '2025-12-31', '2025-12-28', '2025-12-31', 'Y', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(6, 2025, 'QTR', 1, 3, 'Quarter 3', 'Q3', 3, '2026-01-01', '2026-03-14', '2026-03-12', '2026-03-14', 'Y', 'Y', NULL, '2026-02-07 09:25:50', NULL),
(7, 2025, 'QTR', 1, 3, 'Quarter 4', 'Q4', 4, '2026-03-15', '2026-06-12', '2026-06-11', '2026-06-12', 'Y', 'Y', NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `school_periods`
--

CREATE TABLE `school_periods` (
  `period_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` varchar(100) NOT NULL,
  `short_name` varchar(10) DEFAULT NULL,
  `length` int(11) DEFAULT NULL,
  `start_time` varchar(10) DEFAULT NULL,
  `end_time` varchar(10) DEFAULT NULL,
  `block` varchar(10) DEFAULT NULL,
  `attendance` varchar(1) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_periods`
--

INSERT INTO `school_periods` (`period_id`, `syear`, `school_id`, `sort_order`, `title`, `short_name`, `length`, `start_time`, `end_time`, `block`, `attendance`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, 2025, 1, 1, 'Full Day', 'FD', 300, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(2, 2025, 1, 2, 'Half Day AM', 'AM', 150, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(3, 2025, 1, 3, 'Half Day PM', 'PM', 150, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(4, 2025, 1, 4, 'Period 1', '01', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(5, 2025, 1, 5, 'Period 2', '02', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(6, 2025, 1, 6, 'Period 3', '03', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(7, 2025, 1, 7, 'Period 4', '04', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(8, 2025, 1, 8, 'Period 5', '05', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(9, 2025, 1, 9, 'Period 6', '06', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(10, 2025, 1, 10, 'Period 7', '07', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL),
(11, 2025, 1, 11, 'Period 8', '08', 50, NULL, NULL, NULL, 'Y', NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `staff`
--

CREATE TABLE `staff` (
  `syear` decimal(4,0) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `current_school_id` int(11) DEFAULT NULL,
  `title` varchar(5) DEFAULT NULL,
  `first_name` varchar(50) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `middle_name` varchar(50) DEFAULT NULL,
  `name_suffix` varchar(3) DEFAULT NULL,
  `username` varchar(100) DEFAULT NULL,
  `password` varchar(106) DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `custom_200000001` text DEFAULT NULL,
  `profile` varchar(30) DEFAULT NULL,
  `schools` varchar(150) DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `failed_login` int(11) DEFAULT NULL,
  `profile_id` int(11) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff`
--

INSERT INTO `staff` (`syear`, `staff_id`, `current_school_id`, `title`, `first_name`, `last_name`, `middle_name`, `name_suffix`, `username`, `password`, `email`, `custom_200000001`, `profile`, `schools`, `last_login`, `failed_login`, `profile_id`, `rollover_id`, `created_at`, `updated_at`) VALUES
(2025, 1, 1, NULL, 'Admin', 'Administrator', 'A', NULL, 'admin', '$6$1e759a023aed45f7$/uQ7jtJX3TqwjXtDgvn8x.Xvr/53AemY.ARFMa.fydjLwFJvGwjkWIjgcmkwc7F/Caa72YxO7Alar/bAcUJHi1', NULL, NULL, 'admin', ',1,', '2026-02-27 12:12:41', NULL, 1, NULL, '2026-02-07 09:25:50', '2026-02-27 06:42:41'),
(2025, 2, 1, NULL, 'Teach', 'Teacher', 'T', NULL, 'teacher', '$6$cf0dc4c40d38891f$FqKT6nlTer3ujAf8CcQi6ABIEtlow0Va2p6HYh.M6eGWUfpgLr/pfrSwdIcTlV1LDxLg52puVETGMCYKL3vOo/', NULL, NULL, 'teacher', ',1,', NULL, NULL, 2, NULL, '2026-02-07 09:25:50', NULL),
(2025, 3, 1, NULL, 'Parent', 'Parent', 'P', NULL, 'parent', '$6$947c923597601364$Kgbb0Ey3lYTYnqM66VkFRgJVFDW48cBAfNF7t0CVjokL7drcEFId61whqpLrRI1w0q2J2VPfg86Obaf1tG2Ng1', NULL, NULL, 'parent', NULL, NULL, NULL, 3, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `staff_exceptions`
--

CREATE TABLE `staff_exceptions` (
  `user_id` int(11) NOT NULL,
  `modname` varchar(150) NOT NULL,
  `can_use` varchar(1) DEFAULT NULL,
  `can_edit` varchar(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `staff_fields`
--

CREATE TABLE `staff_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) DEFAULT NULL,
  `default_selection` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff_fields`
--

INSERT INTO `staff_fields` (`id`, `type`, `title`, `sort_order`, `select_options`, `category_id`, `required`, `default_selection`, `created_at`, `updated_at`) VALUES
(200000000, 'text', 'Email Address', 0, NULL, 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(200000001, 'text', 'Phone Number', 1, NULL, 1, NULL, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `staff_field_categories`
--

CREATE TABLE `staff_field_categories` (
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `columns` decimal(4,0) DEFAULT NULL,
  `include` varchar(100) DEFAULT NULL,
  `admin` char(1) DEFAULT NULL,
  `teacher` char(1) DEFAULT NULL,
  `parent` char(1) DEFAULT NULL,
  `none` char(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff_field_categories`
--

INSERT INTO `staff_field_categories` (`id`, `title`, `sort_order`, `columns`, `include`, `admin`, `teacher`, `parent`, `none`, `created_at`, `updated_at`) VALUES
(1, 'General Info', 1, NULL, NULL, 'Y', 'Y', 'Y', 'Y', '2026-02-07 09:25:50', NULL),
(2, 'Schedule', 2, NULL, NULL, NULL, 'Y', NULL, NULL, '2026-02-07 09:25:50', NULL),
(3, 'Food Service', 3, NULL, 'Food_Service/User', 'Y', 'Y', NULL, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `students`
--

CREATE TABLE `students` (
  `student_id` int(11) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `middle_name` varchar(50) DEFAULT NULL,
  `name_suffix` varchar(3) DEFAULT NULL,
  `username` varchar(100) DEFAULT NULL,
  `password` varchar(106) DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `failed_login` int(11) DEFAULT NULL,
  `custom_200000000` text DEFAULT NULL,
  `custom_200000001` text DEFAULT NULL,
  `custom_200000002` text DEFAULT NULL,
  `custom_200000003` text DEFAULT NULL,
  `custom_200000004` date DEFAULT NULL,
  `custom_200000005` text DEFAULT NULL,
  `custom_200000006` text DEFAULT NULL,
  `custom_200000007` text DEFAULT NULL,
  `custom_200000008` text DEFAULT NULL,
  `custom_200000009` longtext DEFAULT NULL,
  `custom_200000010` char(1) DEFAULT NULL,
  `custom_200000011` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `students`
--

INSERT INTO `students` (`student_id`, `last_name`, `first_name`, `middle_name`, `name_suffix`, `username`, `password`, `last_login`, `failed_login`, `custom_200000000`, `custom_200000001`, `custom_200000002`, `custom_200000003`, `custom_200000004`, `custom_200000005`, `custom_200000006`, `custom_200000007`, `custom_200000008`, `custom_200000009`, `custom_200000010`, `custom_200000011`, `created_at`, `updated_at`) VALUES
(1, 'Student', 'Student', 'S', NULL, 'student', '$6$f03d507b27b8b9ff$WKtYRdFZGNjRKUr4btzq/p90hbKRAyB8HmrZpgpUhbAh.GtOCveXtXt43IaEDZJ31rVUYZ7ID8xPgKkCiRyzZ1', NULL, NULL, 'Male', 'White, Non-Hispanic', 'Bug', NULL, '2015-12-04', 'English', NULL, NULL, NULL, NULL, NULL, NULL, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `students_join_address`
--

CREATE TABLE `students_join_address` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `address_id` int(11) NOT NULL,
  `contact_seq` decimal(10,0) DEFAULT NULL,
  `gets_mail` varchar(1) DEFAULT NULL,
  `primary_residence` varchar(1) DEFAULT NULL,
  `legal_residence` varchar(1) DEFAULT NULL,
  `am_bus` varchar(1) DEFAULT NULL,
  `pm_bus` varchar(1) DEFAULT NULL,
  `mailing` varchar(1) DEFAULT NULL,
  `residence` varchar(1) DEFAULT NULL,
  `bus` varchar(1) DEFAULT NULL,
  `bus_pickup` varchar(1) DEFAULT NULL,
  `bus_dropoff` varchar(1) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_join_people`
--

CREATE TABLE `students_join_people` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `person_id` int(11) NOT NULL,
  `address_id` int(11) DEFAULT NULL,
  `custody` varchar(1) DEFAULT NULL,
  `emergency` varchar(1) DEFAULT NULL,
  `student_relation` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_join_users`
--

CREATE TABLE `students_join_users` (
  `student_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `students_join_users`
--

INSERT INTO `students_join_users` (`student_id`, `staff_id`, `created_at`, `updated_at`) VALUES
(1, 3, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_assignments`
--

CREATE TABLE `student_assignments` (
  `assignment_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `data` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_eligibility_activities`
--

CREATE TABLE `student_eligibility_activities` (
  `syear` decimal(4,0) DEFAULT NULL,
  `student_id` int(11) NOT NULL,
  `activity_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_enrollment`
--

CREATE TABLE `student_enrollment` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `grade_id` int(11) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `enrollment_code` int(11) DEFAULT NULL,
  `drop_code` int(11) DEFAULT NULL,
  `next_school` int(11) DEFAULT NULL,
  `calendar_id` int(11) DEFAULT NULL,
  `last_school` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_enrollment`
--

INSERT INTO `student_enrollment` (`id`, `syear`, `school_id`, `student_id`, `grade_id`, `start_date`, `end_date`, `enrollment_code`, `drop_code`, `next_school`, `calendar_id`, `last_school`, `created_at`, `updated_at`) VALUES
(1, 2025, 1, 1, 7, '2025-06-06', NULL, 3, NULL, 1, 1, 1, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_enrollment_codes`
--

CREATE TABLE `student_enrollment_codes` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` varchar(100) NOT NULL,
  `short_name` varchar(10) DEFAULT NULL,
  `type` varchar(4) DEFAULT NULL,
  `default_code` varchar(1) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_enrollment_codes`
--

INSERT INTO `student_enrollment_codes` (`id`, `syear`, `title`, `short_name`, `type`, `default_code`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 2025, 'Moved from District', 'MOVE', 'Drop', NULL, 1, '2026-02-07 09:25:50', NULL),
(2, 2025, 'Expelled', 'EXP', 'Drop', NULL, 2, '2026-02-07 09:25:50', NULL),
(3, 2025, 'Beginning of Year', 'EBY', 'Add', 'Y', 3, '2026-02-07 09:25:50', NULL),
(4, 2025, 'From Other District', 'OTHER', 'Add', NULL, 4, '2026-02-07 09:25:50', NULL),
(5, 2025, 'Transferred in District', 'TRAN', 'Drop', NULL, 5, '2026-02-07 09:25:50', NULL),
(6, 2025, 'Transferred in District', 'EMY', 'Add', NULL, 6, '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_field_categories`
--

CREATE TABLE `student_field_categories` (
  `id` int(11) NOT NULL,
  `title` text NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `columns` decimal(4,0) DEFAULT NULL,
  `include` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_field_categories`
--

INSERT INTO `student_field_categories` (`id`, `title`, `sort_order`, `columns`, `include`, `created_at`, `updated_at`) VALUES
(1, 'General Info', 1, NULL, NULL, '2026-02-07 09:25:50', NULL),
(2, 'Medical', 3, NULL, NULL, '2026-02-07 09:25:50', NULL),
(3, 'Addresses & Contacts', 2, NULL, NULL, '2026-02-07 09:25:50', NULL),
(4, 'Comments', 4, NULL, NULL, '2026-02-07 09:25:50', NULL),
(5, 'Food Service', 5, NULL, 'Food_Service/Student', '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_medical`
--

CREATE TABLE `student_medical` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `type` varchar(25) NOT NULL,
  `medical_date` date DEFAULT NULL,
  `comments` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_medical_alerts`
--

CREATE TABLE `student_medical_alerts` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `title` varchar(100) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_medical_visits`
--

CREATE TABLE `student_medical_visits` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `time_in` varchar(20) DEFAULT NULL,
  `time_out` varchar(20) DEFAULT NULL,
  `reason` varchar(100) DEFAULT NULL,
  `result` varchar(100) DEFAULT NULL,
  `comments` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_mp_comments`
--

CREATE TABLE `student_mp_comments` (
  `student_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `comment` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_mp_stats`
--

CREATE TABLE `student_mp_stats` (
  `student_id` int(11) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `cum_weighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_unweighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_rank` int(11) DEFAULT NULL,
  `mp_rank` int(11) DEFAULT NULL,
  `class_size` int(11) DEFAULT NULL,
  `sum_weighted_factors` decimal(22,16) DEFAULT NULL,
  `sum_unweighted_factors` decimal(22,16) DEFAULT NULL,
  `count_weighted_factors` int(11) DEFAULT NULL,
  `count_unweighted_factors` int(11) DEFAULT NULL,
  `grade_level_short` varchar(3) DEFAULT NULL,
  `cr_weighted_factors` decimal(22,16) DEFAULT NULL,
  `cr_unweighted_factors` decimal(22,16) DEFAULT NULL,
  `count_cr_factors` int(11) DEFAULT NULL,
  `cum_cr_weighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_cr_unweighted_factor` decimal(22,16) DEFAULT NULL,
  `credit_attempted` decimal(22,16) DEFAULT NULL,
  `credit_earned` decimal(22,16) DEFAULT NULL,
  `gp_credits` decimal(22,16) DEFAULT NULL,
  `cr_credits` decimal(22,16) DEFAULT NULL,
  `comments` varchar(75) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_report_card_comments`
--

CREATE TABLE `student_report_card_comments` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `report_card_comment_id` int(11) NOT NULL,
  `comment` varchar(5) DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_report_card_grades`
--

CREATE TABLE `student_report_card_grades` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `report_card_grade_id` int(11) DEFAULT NULL,
  `report_card_comment_id` int(11) DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `grade_percent` decimal(4,1) DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `grade_letter` varchar(5) DEFAULT NULL,
  `weighted_gp` decimal(7,2) DEFAULT NULL,
  `unweighted_gp` decimal(7,2) DEFAULT NULL,
  `gp_scale` decimal(7,2) DEFAULT NULL,
  `credit_attempted` decimal(22,16) DEFAULT NULL,
  `credit_earned` decimal(22,16) DEFAULT NULL,
  `credit_category` varchar(10) DEFAULT NULL,
  `course_title` text NOT NULL,
  `id` int(11) NOT NULL,
  `school` text DEFAULT NULL,
  `class_rank` varchar(1) DEFAULT NULL,
  `credit_hours` decimal(6,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Triggers `student_report_card_grades`
--
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_delete` AFTER DELETE ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(OLD.student_id, OLD.marking_period_id)
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_insert` AFTER INSERT ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(NEW.student_id, NEW.marking_period_id)
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_update` AFTER UPDATE ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(NEW.student_id, NEW.marking_period_id)
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `templates`
--

CREATE TABLE `templates` (
  `modname` varchar(150) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `template` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `templates`
--

INSERT INTO `templates` (`modname`, `staff_id`, `template`, `created_at`, `updated_at`) VALUES
('Custom/CreateParents.php', 0, 'Dear __PARENT_NAME__,\n\nA parent account for the __SCHOOL_ID__ has been created to access school information and student information for the following students:\n__ASSOCIATED_STUDENTS__\n\nYour account credentials are:\nUsername: __USERNAME__\nPassword: __PASSWORD__\n\nA link to the SIS website and instructions for access are available on the school\'s website__BLOCK2__Dear __PARENT_NAME__,\n\nThe following students have been added to your parent account on the SIS:\n__ASSOCIATED_STUDENTS__', '2026-02-07 09:25:50', NULL),
('Custom/NotifyParents.php', 0, 'Dear __PARENT_NAME__,\n\nA parent account for the __SCHOOL_ID__ has been created to access school information and student information for the following students:\n__ASSOCIATED_STUDENTS__\n\nYour account credentials are:\nUsername: __USERNAME__\nPassword: __PASSWORD__\n\nA link to the SIS website and instructions for access are available on the school\'s website', '2026-02-07 09:25:50', NULL),
('Grades/HonorRoll.php', 0, '<br /><br /><br />\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\"><strong>__SCHOOL_ID__</strong><br /></span><br /><span style=\"font-size: xx-large;\">We hereby recognize<br /><br /></span></div>\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\"><strong>__FIRST_NAME__ __LAST_NAME__</strong><br /><br /></span></div>\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\">Who has completed all the academic requirements for <br />Honor Roll</span></div>', '2026-02-07 09:25:50', NULL),
('Grades/Transcripts.php', 0, '<h2 style=\"text-align: center;\">Studies Certificate</h2>\n<p>The Principal here undersigned certifies:</p>\n<p>That __FIRST_NAME__ __LAST_NAME__ attended at this school the following courses corresponding to grade __GRADE_ID__ in year __YEAR__ with the following grades and credit hours.</p>\n<p>__BLOCK2__</p>\n<p>&nbsp;</p>\n<table style=\"border-collapse: collapse; width: 100%;\" border=\"0\" cellpadding=\"10\"><tbody><tr>\n<td style=\"width: 50%; text-align: center;\"><hr />\n<p>Signature</p>\n<p>&nbsp;</p><hr />\n<p>Title</p></td>\n<td style=\"width: 50%; text-align: center;\"><hr />\n<p>Signature</p>\n<p>&nbsp;</p><hr />\n<p>Title</p></td></tr></tbody></table>', '2026-02-07 09:25:50', NULL),
('Students/Letters.php', 0, '<p></p>', '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Stand-in structure for view `transcript_grades`
-- (See below for the actual view)
--
CREATE TABLE `transcript_grades` (
`syear` decimal(4,0)
,`school_id` int(11)
,`marking_period_id` int(11)
,`mp_type` varchar(20)
,`short_name` varchar(10)
,`parent_id` int(11)
,`grandparent_id` int(11)
,`parent_end_date` date
,`end_date` date
,`student_id` int(11)
,`cum_weighted_gpa` decimal(32,19)
,`cum_unweighted_gpa` decimal(32,19)
,`cum_rank` int(11)
,`mp_rank` int(11)
,`class_size` int(11)
,`weighted_gpa` decimal(36,23)
,`unweighted_gpa` decimal(36,23)
,`grade_level_short` varchar(3)
,`comment` text
,`grade_percent` decimal(4,1)
,`grade_letter` varchar(5)
,`weighted_gp` decimal(7,2)
,`unweighted_gp` decimal(7,2)
,`gp_scale` decimal(7,2)
,`credit_attempted` decimal(22,16)
,`credit_earned` decimal(22,16)
,`course_title` text
,`school_name` text
,`school_scale` decimal(10,3)
,`cr_weighted_gpa` decimal(36,23)
,`cr_unweighted_gpa` decimal(36,23)
,`cum_cr_weighted_gpa` decimal(32,19)
,`cum_cr_unweighted_gpa` decimal(32,19)
,`class_rank` varchar(1)
,`comments` varchar(75)
,`credit_hours` decimal(6,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `user_profiles`
--

CREATE TABLE `user_profiles` (
  `id` int(11) NOT NULL,
  `profile` varchar(30) DEFAULT NULL,
  `title` text NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `user_profiles`
--

INSERT INTO `user_profiles` (`id`, `profile`, `title`, `created_at`, `updated_at`) VALUES
(0, 'student', 'Student', '2026-02-07 09:25:50', NULL),
(1, 'admin', 'Administrator', '2026-02-07 09:25:50', NULL),
(2, 'teacher', 'Teacher', '2026-02-07 09:25:50', NULL),
(3, 'parent', 'Parent', '2026-02-07 09:25:50', NULL);

-- --------------------------------------------------------

--
-- Structure for view `course_details`
--
DROP TABLE IF EXISTS `course_details`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `course_details`  AS SELECT `cp`.`school_id` AS `school_id`, `cp`.`syear` AS `syear`, `cp`.`marking_period_id` AS `marking_period_id`, `c`.`subject_id` AS `subject_id`, `cp`.`course_id` AS `course_id`, `cp`.`course_period_id` AS `course_period_id`, `cp`.`teacher_id` AS `teacher_id`, `c`.`title` AS `course_title`, `cp`.`title` AS `cp_title`, `cp`.`grade_scale_id` AS `grade_scale_id`, `cp`.`mp` AS `mp`, `cp`.`credits` AS `credits` FROM (`course_periods` `cp` join `courses` `c`) WHERE `cp`.`course_id` = `c`.`course_id` ;

-- --------------------------------------------------------

--
-- Structure for view `enroll_grade`
--
DROP TABLE IF EXISTS `enroll_grade`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `enroll_grade`  AS SELECT `e`.`id` AS `id`, `e`.`syear` AS `syear`, `e`.`school_id` AS `school_id`, `e`.`student_id` AS `student_id`, `e`.`start_date` AS `start_date`, `e`.`end_date` AS `end_date`, `sg`.`short_name` AS `short_name`, `sg`.`title` AS `title` FROM (`student_enrollment` `e` join `school_gradelevels` `sg`) WHERE `e`.`grade_id` = `sg`.`id` ;

-- --------------------------------------------------------

--
-- Structure for view `marking_periods`
--
DROP TABLE IF EXISTS `marking_periods`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `marking_periods`  AS SELECT `school_marking_periods`.`marking_period_id` AS `marking_period_id`, 'Rosario' AS `mp_source`, `school_marking_periods`.`syear` AS `syear`, `school_marking_periods`.`school_id` AS `school_id`, CASE WHEN `school_marking_periods`.`mp` = 'FY' THEN 'year' WHEN `school_marking_periods`.`mp` = 'SEM' THEN 'semester' WHEN `school_marking_periods`.`mp` = 'QTR' THEN 'quarter' ELSE NULL END AS `mp_type`, `school_marking_periods`.`title` AS `title`, `school_marking_periods`.`short_name` AS `short_name`, `school_marking_periods`.`sort_order` AS `sort_order`, CASE WHEN `school_marking_periods`.`parent_id` > 0 THEN `school_marking_periods`.`parent_id` ELSE -1 END AS `parent_id`, CASE WHEN (select `smp`.`parent_id` from `school_marking_periods` `smp` where `smp`.`marking_period_id` = `school_marking_periods`.`parent_id`) > 0 THEN (select `smp`.`parent_id` from `school_marking_periods` `smp` where `smp`.`marking_period_id` = `school_marking_periods`.`parent_id`) ELSE -1 END AS `grandparent_id`, `school_marking_periods`.`start_date` AS `start_date`, `school_marking_periods`.`end_date` AS `end_date`, `school_marking_periods`.`post_start_date` AS `post_start_date`, `school_marking_periods`.`post_end_date` AS `post_end_date`, `school_marking_periods`.`does_grades` AS `does_grades`, `school_marking_periods`.`does_comments` AS `does_comments` FROM `school_marking_periods`union select `history_marking_periods`.`marking_period_id` AS `marking_period_id`,'History' AS `mp_source`,`history_marking_periods`.`syear` AS `syear`,`history_marking_periods`.`school_id` AS `school_id`,`history_marking_periods`.`mp_type` AS `mp_type`,`history_marking_periods`.`name` AS `title`,`history_marking_periods`.`short_name` AS `short_name`,NULL AS `sort_order`,`history_marking_periods`.`parent_id` AS `parent_id`,-1 AS `grandparent_id`,NULL AS `start_date`,`history_marking_periods`.`post_end_date` AS `end_date`,NULL AS `post_start_date`,`history_marking_periods`.`post_end_date` AS `post_end_date`,'Y' AS `does_grades`,NULL AS `does_comments` from `history_marking_periods`  ;

-- --------------------------------------------------------

--
-- Structure for view `transcript_grades`
--
DROP TABLE IF EXISTS `transcript_grades`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `transcript_grades`  AS SELECT `mp`.`syear` AS `syear`, `mp`.`school_id` AS `school_id`, `mp`.`marking_period_id` AS `marking_period_id`, `mp`.`mp_type` AS `mp_type`, `mp`.`short_name` AS `short_name`, `mp`.`parent_id` AS `parent_id`, `mp`.`grandparent_id` AS `grandparent_id`, (select `mp2`.`end_date` from (`student_report_card_grades` join `marking_periods` `mp2` on(`mp2`.`marking_period_id` = `student_report_card_grades`.`marking_period_id`)) where `student_report_card_grades`.`student_id` = `sms`.`student_id` and (`student_report_card_grades`.`marking_period_id` = `mp`.`parent_id` or `student_report_card_grades`.`marking_period_id` = `mp`.`grandparent_id`) and `student_report_card_grades`.`course_title` = `srcg`.`course_title` order by `mp2`.`end_date` limit 1) AS `parent_end_date`, `mp`.`end_date` AS `end_date`, `sms`.`student_id` AS `student_id`, `sms`.`cum_weighted_factor`* coalesce(`schools`.`reporting_gp_scale`,(select `schools`.`reporting_gp_scale` from `schools` where `mp`.`school_id` = `schools`.`id` order by `schools`.`syear` limit 1)) AS `cum_weighted_gpa`, `sms`.`cum_unweighted_factor`* `schools`.`reporting_gp_scale` AS `cum_unweighted_gpa`, `sms`.`cum_rank` AS `cum_rank`, `sms`.`mp_rank` AS `mp_rank`, `sms`.`class_size` AS `class_size`, `sms`.`sum_weighted_factors`/ `sms`.`count_weighted_factors` * `schools`.`reporting_gp_scale` AS `weighted_gpa`, `sms`.`sum_unweighted_factors`/ `sms`.`count_unweighted_factors` * `schools`.`reporting_gp_scale` AS `unweighted_gpa`, `sms`.`grade_level_short` AS `grade_level_short`, `srcg`.`comment` AS `comment`, `srcg`.`grade_percent` AS `grade_percent`, `srcg`.`grade_letter` AS `grade_letter`, `srcg`.`weighted_gp` AS `weighted_gp`, `srcg`.`unweighted_gp` AS `unweighted_gp`, `srcg`.`gp_scale` AS `gp_scale`, `srcg`.`credit_attempted` AS `credit_attempted`, `srcg`.`credit_earned` AS `credit_earned`, `srcg`.`course_title` AS `course_title`, `srcg`.`school` AS `school_name`, `schools`.`reporting_gp_scale` AS `school_scale`, `sms`.`cr_weighted_factors`/ `sms`.`count_cr_factors` * `schools`.`reporting_gp_scale` AS `cr_weighted_gpa`, `sms`.`cr_unweighted_factors`/ `sms`.`count_cr_factors` * `schools`.`reporting_gp_scale` AS `cr_unweighted_gpa`, `sms`.`cum_cr_weighted_factor`* `schools`.`reporting_gp_scale` AS `cum_cr_weighted_gpa`, `sms`.`cum_cr_unweighted_factor`* `schools`.`reporting_gp_scale` AS `cum_cr_unweighted_gpa`, `srcg`.`class_rank` AS `class_rank`, `sms`.`comments` AS `comments`, `srcg`.`credit_hours` AS `credit_hours` FROM (((`marking_periods` `mp` join `student_report_card_grades` `srcg` on(`mp`.`marking_period_id` = `srcg`.`marking_period_id`)) join `student_mp_stats` `sms` on(`sms`.`marking_period_id` = `mp`.`marking_period_id` and `sms`.`student_id` = `srcg`.`student_id`)) left join `schools` on(`mp`.`school_id` = `schools`.`id` and `mp`.`syear` = `schools`.`syear`)) ORDER BY `srcg`.`course_period_id` ASC ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `accounting_categories`
--
ALTER TABLE `accounting_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `category_id` (`category_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `accounting_payments_ind1` (`staff_id`),
  ADD KEY `accounting_payments_ind2` (`amount`);

--
-- Indexes for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  ADD PRIMARY KEY (`id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `address`
--
ALTER TABLE `address`
  ADD PRIMARY KEY (`address_id`),
  ADD KEY `address_3` (`zipcode`),
  ADD KEY `address_4` (`street`);

--
-- Indexes for table `address_fields`
--
ALTER TABLE `address_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `address_desc_ind2` (`type`),
  ADD KEY `address_fields_ind3` (`category_id`);

--
-- Indexes for table `address_field_categories`
--
ALTER TABLE `address_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `attendance_calendar`
--
ALTER TABLE `attendance_calendar`
  ADD PRIMARY KEY (`syear`,`school_id`,`school_date`,`calendar_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  ADD PRIMARY KEY (`calendar_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `attendance_codes_ind3` (`short_name`);

--
-- Indexes for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_completed`
--
ALTER TABLE `attendance_completed`
  ADD PRIMARY KEY (`staff_id`,`school_date`,`period_id`,`table_name`);

--
-- Indexes for table `attendance_day`
--
ALTER TABLE `attendance_day`
  ADD PRIMARY KEY (`student_id`,`school_date`),
  ADD KEY `marking_period_id` (`marking_period_id`);

--
-- Indexes for table `attendance_period`
--
ALTER TABLE `attendance_period`
  ADD PRIMARY KEY (`student_id`,`school_date`,`period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `attendance_period_ind1` (`student_id`),
  ADD KEY `attendance_period_ind2` (`period_id`),
  ADD KEY `attendance_period_ind4` (`school_date`),
  ADD KEY `attendance_period_ind5` (`attendance_code`);

--
-- Indexes for table `billing_fees`
--
ALTER TABLE `billing_fees`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `billing_payments`
--
ALTER TABLE `billing_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `billing_payments_ind2` (`amount`),
  ADD KEY `billing_payments_ind3` (`refunded_payment_id`);

--
-- Indexes for table `calendar_events`
--
ALTER TABLE `calendar_events`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`course_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `courses_ind2` (`subject_id`);

--
-- Indexes for table `course_periods`
--
ALTER TABLE `course_periods`
  ADD PRIMARY KEY (`course_period_id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `teacher_id` (`teacher_id`),
  ADD KEY `secondary_teacher_id` (`secondary_teacher_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  ADD PRIMARY KEY (`course_period_school_periods_id`),
  ADD UNIQUE KEY `course_period_id` (`course_period_id`,`period_id`);

--
-- Indexes for table `course_subjects`
--
ALTER TABLE `course_subjects`
  ADD PRIMARY KEY (`subject_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `csp_reports`
--
ALTER TABLE `csp_reports`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `custom_fields`
--
ALTER TABLE `custom_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `custom_desc_ind2` (`type`),
  ADD KEY `custom_fields_ind3` (`category_id`);

--
-- Indexes for table `discipline_fields`
--
ALTER TABLE `discipline_fields`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `eligibility`
--
ALTER TABLE `eligibility`
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `eligibility_ind1` (`student_id`,`course_period_id`,`school_date`);

--
-- Indexes for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `eligibility_completed`
--
ALTER TABLE `eligibility_completed`
  ADD PRIMARY KEY (`staff_id`,`school_date`,`period_id`);

--
-- Indexes for table `food_service_accounts`
--
ALTER TABLE `food_service_accounts`
  ADD PRIMARY KEY (`account_id`);

--
-- Indexes for table `food_service_categories`
--
ALTER TABLE `food_service_categories`
  ADD PRIMARY KEY (`category_id`),
  ADD UNIQUE KEY `food_service_categories_title` (`school_id`,`menu_id`,`title`);

--
-- Indexes for table `food_service_items`
--
ALTER TABLE `food_service_items`
  ADD PRIMARY KEY (`item_id`),
  ADD UNIQUE KEY `food_service_items_short_name` (`school_id`,`short_name`);

--
-- Indexes for table `food_service_menus`
--
ALTER TABLE `food_service_menus`
  ADD PRIMARY KEY (`menu_id`),
  ADD UNIQUE KEY `food_service_menus_title` (`school_id`,`title`);

--
-- Indexes for table `food_service_menu_items`
--
ALTER TABLE `food_service_menu_items`
  ADD PRIMARY KEY (`menu_item_id`);

--
-- Indexes for table `food_service_staff_accounts`
--
ALTER TABLE `food_service_staff_accounts`
  ADD PRIMARY KEY (`staff_id`),
  ADD UNIQUE KEY `barcode` (`barcode`);

--
-- Indexes for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  ADD PRIMARY KEY (`transaction_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `food_service_staff_transaction_items`
--
ALTER TABLE `food_service_staff_transaction_items`
  ADD PRIMARY KEY (`item_id`,`transaction_id`),
  ADD KEY `transaction_id` (`transaction_id`);

--
-- Indexes for table `food_service_student_accounts`
--
ALTER TABLE `food_service_student_accounts`
  ADD PRIMARY KEY (`student_id`),
  ADD UNIQUE KEY `barcode` (`barcode`);

--
-- Indexes for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  ADD PRIMARY KEY (`transaction_id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `food_service_transaction_items`
--
ALTER TABLE `food_service_transaction_items`
  ADD PRIMARY KEY (`item_id`,`transaction_id`),
  ADD KEY `transaction_id` (`transaction_id`);

--
-- Indexes for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  ADD PRIMARY KEY (`assignment_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `gradebook_assignments_ind3` (`assignment_type_id`);

--
-- Indexes for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  ADD PRIMARY KEY (`assignment_type_id`),
  ADD KEY `staff_id` (`staff_id`),
  ADD KEY `course_id` (`course_id`);

--
-- Indexes for table `gradebook_grades`
--
ALTER TABLE `gradebook_grades`
  ADD PRIMARY KEY (`student_id`,`assignment_id`,`course_period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `gradebook_grades_ind1` (`assignment_id`);

--
-- Indexes for table `grades_completed`
--
ALTER TABLE `grades_completed`
  ADD PRIMARY KEY (`staff_id`,`marking_period_id`,`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `course_period_id` (`course_period_id`);

--
-- Indexes for table `history_marking_periods`
--
ALTER TABLE `history_marking_periods`
  ADD PRIMARY KEY (`marking_period_id`),
  ADD KEY `history_marking_period_ind1` (`school_id`),
  ADD KEY `history_marking_period_ind2` (`syear`);

--
-- Indexes for table `lunch_period`
--
ALTER TABLE `lunch_period`
  ADD PRIMARY KEY (`student_id`,`school_date`,`period_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `lunch_period_ind2` (`period_id`),
  ADD KEY `lunch_period_ind3` (`attendance_code`),
  ADD KEY `lunch_period_ind4` (`school_date`);

--
-- Indexes for table `moodlexrosario`
--
ALTER TABLE `moodlexrosario`
  ADD PRIMARY KEY (`column`,`rosario_id`);

--
-- Indexes for table `people`
--
ALTER TABLE `people`
  ADD PRIMARY KEY (`person_id`),
  ADD KEY `people_1` (`last_name`,`first_name`);

--
-- Indexes for table `people_fields`
--
ALTER TABLE `people_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `people_desc_ind2` (`type`),
  ADD KEY `people_fields_ind3` (`category_id`);

--
-- Indexes for table `people_field_categories`
--
ALTER TABLE `people_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `people_join_contacts`
--
ALTER TABLE `people_join_contacts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `people_join_contacts_ind1` (`person_id`);

--
-- Indexes for table `portal_notes`
--
ALTER TABLE `portal_notes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `portal_polls`
--
ALTER TABLE `portal_polls`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `portal_poll_questions`
--
ALTER TABLE `portal_poll_questions`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `profile_exceptions`
--
ALTER TABLE `profile_exceptions`
  ADD PRIMARY KEY (`profile_id`,`modname`);

--
-- Indexes for table `program_config`
--
ALTER TABLE `program_config`
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `program_user_config`
--
ALTER TABLE `program_user_config`
  ADD KEY `program_user_config_ind1` (`user_id`,`program`);

--
-- Indexes for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_comment_codes`
--
ALTER TABLE `report_card_comment_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `report_card_comment_codes_ind1` (`school_id`);

--
-- Indexes for table `report_card_comment_code_scales`
--
ALTER TABLE `report_card_comment_code_scales`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `resources`
--
ALTER TABLE `resources`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `schedule`
--
ALTER TABLE `schedule`
  ADD KEY `course_id` (`course_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `schedule_ind3` (`student_id`,`marking_period_id`,`start_date`,`end_date`);

--
-- Indexes for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  ADD PRIMARY KEY (`request_id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `schedule_requests_ind1` (`student_id`,`course_id`,`syear`);

--
-- Indexes for table `schools`
--
ALTER TABLE `schools`
  ADD PRIMARY KEY (`id`,`syear`),
  ADD KEY `schools_ind1` (`syear`);

--
-- Indexes for table `school_fields`
--
ALTER TABLE `school_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_desc_ind2` (`type`);

--
-- Indexes for table `school_gradelevels`
--
ALTER TABLE `school_gradelevels`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_gradelevels_ind1` (`school_id`);

--
-- Indexes for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  ADD PRIMARY KEY (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `school_marking_periods_ind1` (`parent_id`),
  ADD KEY `school_marking_periods_ind2` (`syear`,`school_id`,`start_date`,`end_date`);

--
-- Indexes for table `school_periods`
--
ALTER TABLE `school_periods`
  ADD PRIMARY KEY (`period_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `staff`
--
ALTER TABLE `staff`
  ADD PRIMARY KEY (`staff_id`),
  ADD UNIQUE KEY `staff_ind4` (`username`,`syear`),
  ADD KEY `staff_ind1` (`staff_id`,`syear`),
  ADD KEY `staff_ind2` (`last_name`,`first_name`),
  ADD KEY `staff_ind3` (`schools`);

--
-- Indexes for table `staff_exceptions`
--
ALTER TABLE `staff_exceptions`
  ADD PRIMARY KEY (`user_id`,`modname`);

--
-- Indexes for table `staff_fields`
--
ALTER TABLE `staff_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `staff_desc_ind2` (`type`),
  ADD KEY `staff_fields_ind3` (`category_id`);

--
-- Indexes for table `staff_field_categories`
--
ALTER TABLE `staff_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `students`
--
ALTER TABLE `students`
  ADD PRIMARY KEY (`student_id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD KEY `name` (`last_name`,`first_name`,`middle_name`);

--
-- Indexes for table `students_join_address`
--
ALTER TABLE `students_join_address`
  ADD PRIMARY KEY (`id`),
  ADD KEY `stu_addr_meets_2` (`address_id`),
  ADD KEY `students_join_address_ind1` (`student_id`);

--
-- Indexes for table `students_join_people`
--
ALTER TABLE `students_join_people`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `relations_meets_2` (`address_id`);

--
-- Indexes for table `students_join_users`
--
ALTER TABLE `students_join_users`
  ADD PRIMARY KEY (`student_id`,`staff_id`),
  ADD KEY `staff_id` (`staff_id`);

--
-- Indexes for table `student_assignments`
--
ALTER TABLE `student_assignments`
  ADD PRIMARY KEY (`assignment_id`,`student_id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_eligibility_activities`
--
ALTER TABLE `student_eligibility_activities`
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `student_enrollment_2` (`grade_id`),
  ADD KEY `student_enrollment_4` (`start_date`,`end_date`);

--
-- Indexes for table `student_enrollment_codes`
--
ALTER TABLE `student_enrollment_codes`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_field_categories`
--
ALTER TABLE `student_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_medical`
--
ALTER TABLE `student_medical`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`);

--
-- Indexes for table `student_mp_comments`
--
ALTER TABLE `student_mp_comments`
  ADD PRIMARY KEY (`student_id`,`syear`,`marking_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`);

--
-- Indexes for table `student_mp_stats`
--
ALTER TABLE `student_mp_stats`
  ADD PRIMARY KEY (`student_id`,`marking_period_id`);

--
-- Indexes for table `student_report_card_comments`
--
ALTER TABLE `student_report_card_comments`
  ADD PRIMARY KEY (`syear`,`student_id`,`course_period_id`,`marking_period_id`,`report_card_comment_id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `marking_period_id` (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `course_period_id` (`course_period_id`),
  ADD KEY `student_report_card_grades_ind4` (`marking_period_id`);

--
-- Indexes for table `templates`
--
ALTER TABLE `templates`
  ADD PRIMARY KEY (`modname`,`staff_id`);

--
-- Indexes for table `user_profiles`
--
ALTER TABLE `user_profiles`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `accounting_categories`
--
ALTER TABLE `accounting_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address`
--
ALTER TABLE `address`
  MODIFY `address_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address_fields`
--
ALTER TABLE `address_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address_field_categories`
--
ALTER TABLE `address_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  MODIFY `calendar_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `billing_fees`
--
ALTER TABLE `billing_fees`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `billing_payments`
--
ALTER TABLE `billing_payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `calendar_events`
--
ALTER TABLE `calendar_events`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `courses`
--
ALTER TABLE `courses`
  MODIFY `course_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_periods`
--
ALTER TABLE `course_periods`
  MODIFY `course_period_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  MODIFY `course_period_school_periods_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_subjects`
--
ALTER TABLE `course_subjects`
  MODIFY `subject_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `csp_reports`
--
ALTER TABLE `csp_reports`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `custom_fields`
--
ALTER TABLE `custom_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=200000012;

--
-- AUTO_INCREMENT for table `discipline_fields`
--
ALTER TABLE `discipline_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `food_service_categories`
--
ALTER TABLE `food_service_categories`
  MODIFY `category_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `food_service_items`
--
ALTER TABLE `food_service_items`
  MODIFY `item_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `food_service_menus`
--
ALTER TABLE `food_service_menus`
  MODIFY `menu_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `food_service_menu_items`
--
ALTER TABLE `food_service_menu_items`
  MODIFY `menu_item_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  MODIFY `transaction_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  MODIFY `transaction_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  MODIFY `assignment_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  MODIFY `assignment_type_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people`
--
ALTER TABLE `people`
  MODIFY `person_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_fields`
--
ALTER TABLE `people_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_field_categories`
--
ALTER TABLE `people_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_join_contacts`
--
ALTER TABLE `people_join_contacts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_notes`
--
ALTER TABLE `portal_notes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_polls`
--
ALTER TABLE `portal_polls`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_poll_questions`
--
ALTER TABLE `portal_poll_questions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comment_codes`
--
ALTER TABLE `report_card_comment_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comment_code_scales`
--
ALTER TABLE `report_card_comment_code_scales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `resources`
--
ALTER TABLE `resources`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  MODIFY `request_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `schools`
--
ALTER TABLE `schools`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `school_fields`
--
ALTER TABLE `school_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `school_gradelevels`
--
ALTER TABLE `school_gradelevels`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  MODIFY `marking_period_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `school_periods`
--
ALTER TABLE `school_periods`
  MODIFY `period_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `staff`
--
ALTER TABLE `staff`
  MODIFY `staff_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `staff_fields`
--
ALTER TABLE `staff_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=200000002;

--
-- AUTO_INCREMENT for table `staff_field_categories`
--
ALTER TABLE `staff_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `students`
--
ALTER TABLE `students`
  MODIFY `student_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `students_join_address`
--
ALTER TABLE `students_join_address`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students_join_people`
--
ALTER TABLE `students_join_people`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `student_enrollment_codes`
--
ALTER TABLE `student_enrollment_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `student_field_categories`
--
ALTER TABLE `student_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `student_medical`
--
ALTER TABLE `student_medical`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `user_profiles`
--
ALTER TABLE `user_profiles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  ADD CONSTRAINT `accounting_incomes_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `accounting_categories` (`id`),
  ADD CONSTRAINT `accounting_incomes_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  ADD CONSTRAINT `accounting_payments_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `accounting_payments_ibfk_2` FOREIGN KEY (`category_id`) REFERENCES `accounting_categories` (`id`),
  ADD CONSTRAINT `accounting_payments_ibfk_3` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  ADD CONSTRAINT `accounting_salaries_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `accounting_salaries_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_calendar`
--
ALTER TABLE `attendance_calendar`
  ADD CONSTRAINT `attendance_calendar_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  ADD CONSTRAINT `attendance_calendars_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  ADD CONSTRAINT `attendance_codes_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  ADD CONSTRAINT `attendance_code_categories_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_completed`
--
ALTER TABLE `attendance_completed`
  ADD CONSTRAINT `attendance_completed_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `attendance_day`
--
ALTER TABLE `attendance_day`
  ADD CONSTRAINT `attendance_day_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `attendance_day_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `attendance_period`
--
ALTER TABLE `attendance_period`
  ADD CONSTRAINT `attendance_period_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `attendance_period_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `attendance_period_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `billing_fees`
--
ALTER TABLE `billing_fees`
  ADD CONSTRAINT `billing_fees_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `billing_fees_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `billing_payments`
--
ALTER TABLE `billing_payments`
  ADD CONSTRAINT `billing_payments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `billing_payments_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `calendar_events`
--
ALTER TABLE `calendar_events`
  ADD CONSTRAINT `calendar_events_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `courses`
--
ALTER TABLE `courses`
  ADD CONSTRAINT `courses_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `course_periods`
--
ALTER TABLE `course_periods`
  ADD CONSTRAINT `course_periods_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `course_periods_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `course_periods_ibfk_3` FOREIGN KEY (`teacher_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `course_periods_ibfk_4` FOREIGN KEY (`secondary_teacher_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `course_periods_ibfk_5` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  ADD CONSTRAINT `course_period_school_periods_ibfk_1` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `course_subjects`
--
ALTER TABLE `course_subjects`
  ADD CONSTRAINT `course_subjects_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  ADD CONSTRAINT `discipline_field_usage_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  ADD CONSTRAINT `discipline_referrals_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `discipline_referrals_ibfk_2` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `discipline_referrals_ibfk_3` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `eligibility`
--
ALTER TABLE `eligibility`
  ADD CONSTRAINT `eligibility_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `eligibility_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  ADD CONSTRAINT `eligibility_activities_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `eligibility_completed`
--
ALTER TABLE `eligibility_completed`
  ADD CONSTRAINT `eligibility_completed_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `food_service_staff_accounts`
--
ALTER TABLE `food_service_staff_accounts`
  ADD CONSTRAINT `food_service_staff_accounts_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  ADD CONSTRAINT `food_service_staff_transactions_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `food_service_staff_transactions_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `food_service_staff_transaction_items`
--
ALTER TABLE `food_service_staff_transaction_items`
  ADD CONSTRAINT `food_service_staff_transaction_items_ibfk_1` FOREIGN KEY (`transaction_id`) REFERENCES `food_service_staff_transactions` (`transaction_id`);

--
-- Constraints for table `food_service_student_accounts`
--
ALTER TABLE `food_service_student_accounts`
  ADD CONSTRAINT `food_service_student_accounts_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  ADD CONSTRAINT `food_service_transactions_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `food_service_transactions_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `food_service_transaction_items`
--
ALTER TABLE `food_service_transaction_items`
  ADD CONSTRAINT `food_service_transaction_items_ibfk_1` FOREIGN KEY (`transaction_id`) REFERENCES `food_service_transactions` (`transaction_id`);

--
-- Constraints for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  ADD CONSTRAINT `gradebook_assignments_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `gradebook_assignments_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `gradebook_assignments_ibfk_3` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `gradebook_assignments_ibfk_4` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`);

--
-- Constraints for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  ADD CONSTRAINT `gradebook_assignment_types_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `gradebook_assignment_types_ibfk_2` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`);

--
-- Constraints for table `gradebook_grades`
--
ALTER TABLE `gradebook_grades`
  ADD CONSTRAINT `gradebook_grades_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `gradebook_grades_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `grades_completed`
--
ALTER TABLE `grades_completed`
  ADD CONSTRAINT `grades_completed_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`),
  ADD CONSTRAINT `grades_completed_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `grades_completed_ibfk_3` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);

--
-- Constraints for table `lunch_period`
--
ALTER TABLE `lunch_period`
  ADD CONSTRAINT `lunch_period_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `lunch_period_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `lunch_period_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `portal_notes`
--
ALTER TABLE `portal_notes`
  ADD CONSTRAINT `portal_notes_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `portal_polls`
--
ALTER TABLE `portal_polls`
  ADD CONSTRAINT `portal_polls_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `program_config`
--
ALTER TABLE `program_config`
  ADD CONSTRAINT `program_config_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  ADD CONSTRAINT `report_card_comments_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  ADD CONSTRAINT `report_card_comment_categories_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `report_card_comment_categories_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  ADD CONSTRAINT `report_card_grades_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  ADD CONSTRAINT `report_card_grade_scales_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `schedule`
--
ALTER TABLE `schedule`
  ADD CONSTRAINT `schedule_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `schedule_ibfk_2` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `schedule_ibfk_3` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `schedule_ibfk_4` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `schedule_ibfk_5` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  ADD CONSTRAINT `schedule_requests_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `schedule_requests_ibfk_2` FOREIGN KEY (`course_id`) REFERENCES `courses` (`course_id`),
  ADD CONSTRAINT `schedule_requests_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `schedule_requests_ibfk_4` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  ADD CONSTRAINT `school_marking_periods_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `school_periods`
--
ALTER TABLE `school_periods`
  ADD CONSTRAINT `school_periods_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `staff_exceptions`
--
ALTER TABLE `staff_exceptions`
  ADD CONSTRAINT `staff_exceptions_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `students_join_address`
--
ALTER TABLE `students_join_address`
  ADD CONSTRAINT `students_join_address_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `students_join_people`
--
ALTER TABLE `students_join_people`
  ADD CONSTRAINT `students_join_people_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `students_join_users`
--
ALTER TABLE `students_join_users`
  ADD CONSTRAINT `students_join_users_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `students_join_users_ibfk_2` FOREIGN KEY (`staff_id`) REFERENCES `staff` (`staff_id`);

--
-- Constraints for table `student_assignments`
--
ALTER TABLE `student_assignments`
  ADD CONSTRAINT `student_assignments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_eligibility_activities`
--
ALTER TABLE `student_eligibility_activities`
  ADD CONSTRAINT `student_eligibility_activities_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  ADD CONSTRAINT `student_enrollment_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_enrollment_ibfk_2` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `student_medical`
--
ALTER TABLE `student_medical`
  ADD CONSTRAINT `student_medical_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  ADD CONSTRAINT `student_medical_alerts_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  ADD CONSTRAINT `student_medical_visits_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_mp_comments`
--
ALTER TABLE `student_mp_comments`
  ADD CONSTRAINT `student_mp_comments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_mp_comments_ibfk_2` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`);

--
-- Constraints for table `student_mp_stats`
--
ALTER TABLE `student_mp_stats`
  ADD CONSTRAINT `student_mp_stats_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`);

--
-- Constraints for table `student_report_card_comments`
--
ALTER TABLE `student_report_card_comments`
  ADD CONSTRAINT `student_report_card_comments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_report_card_comments_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`),
  ADD CONSTRAINT `student_report_card_comments_ibfk_3` FOREIGN KEY (`marking_period_id`) REFERENCES `school_marking_periods` (`marking_period_id`),
  ADD CONSTRAINT `student_report_card_comments_ibfk_4` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  ADD CONSTRAINT `student_report_card_grades_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`student_id`),
  ADD CONSTRAINT `student_report_card_grades_ibfk_2` FOREIGN KEY (`course_period_id`) REFERENCES `course_periods` (`course_period_id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
