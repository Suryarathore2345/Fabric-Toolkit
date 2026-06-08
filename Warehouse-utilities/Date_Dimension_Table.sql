-- ============================================================
-- DATE DIMENSION - Microsoft Fabric Warehouse (T-SQL)
-- Date Range : 2025-01-01 to 2035-12-31
-- Fiscal Year: April start (month >= 4 → new FY)
-- ============================================================

-- ------------------------------------------------------------
-- STEP 1: Drop & recreate table
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.DimDate', 'U') IS NOT NULL
    DROP TABLE dbo.DimDate;

CREATE TABLE dbo.DimDate
(
    Date            DATE            NOT NULL,
    Date_ID         CHAR(8)         NOT NULL,   -- yyyyMMdd
    DayOfMonth      INT             NOT NULL,   -- 1–31
    DayName         VARCHAR(3)      NOT NULL,   -- Mon, Tue … Sun
    DayOfWeek       INT             NOT NULL,   -- 1=Sun … 7=Sat
    IsWeekDay       BIT             NOT NULL,   -- 0 on Sat/Sun
    Month           INT             NOT NULL,   -- 1–12
    WeekOfMonth     INT             NOT NULL,   -- ceil(DayOfMonth / 7)
    Year            SMALLINT        NOT NULL,   -- e.g. 2025
    WeekOfYear      INT             NOT NULL,   -- ISO week 1–53
    QuarterName     VARCHAR(4)      NOT NULL,   -- Q-1 … Q-4
    QuarterYear     VARCHAR(10)     NOT NULL,   -- Q-1,25
    FiscalYear      VARCHAR(9)      NOT NULL,   -- 2025-2026
    FiscalYearName  VARCHAR(12)     NOT NULL,   -- FYI 25-26
    IsLeapYear      BIT             NOT NULL,
    IsWorkingDay    BIT             NOT NULL,
    IsHoliday       BIT             NOT NULL,
    HolidayName     VARCHAR(100)    NULL,
    IsBusinessDay   BIT             NOT NULL
);


-- ------------------------------------------------------------
-- STEP 2: Populate using GENERATE_SERIES()
--         Generates one integer per day offset from start date
--         No recursion, no hints, no workarounds needed
-- ------------------------------------------------------------
DECLARE @StartDate DATE = '2025-01-01';
DECLARE @EndDate   DATE = '2035-12-31';

INSERT INTO dbo.DimDate
(
    Date, Date_ID,
    DayOfMonth, DayName, DayOfWeek, IsWeekDay,
    Month, WeekOfMonth, Year, WeekOfYear,
    QuarterName, QuarterYear,
    FiscalYear, FiscalYearName,
    IsLeapYear,
    IsWorkingDay, IsHoliday, HolidayName, IsBusinessDay
)
SELECT
    -- ── Keys ─────────────────────────────────────────────────────
    cal_date                                                AS Date,
    CONVERT(CHAR(8), cal_date, 112)                        AS Date_ID,

    -- ── Day ──────────────────────────────────────────────────────
    CAST(DAY(cal_date) AS TINYINT)                         AS DayOfMonth,
    LEFT(DATENAME(WEEKDAY, cal_date), 3)                   AS DayName,
    CAST(DATEPART(WEEKDAY, cal_date) AS TINYINT)           AS DayOfWeek,

    CAST(
        CASE WHEN DATEPART(WEEKDAY, cal_date) IN (1, 7) THEN 0 ELSE 1 END
    AS BIT)                                                AS IsWeekDay,

    -- ── Month / Week ─────────────────────────────────────────────
    CAST(MONTH(cal_date) AS TINYINT)                       AS Month,
    CAST(CEILING(DAY(cal_date) / 7.0) AS TINYINT)         AS WeekOfMonth,
    CAST(YEAR(cal_date) AS SMALLINT)                       AS Year,
    CAST(DATEPART(ISO_WEEK, cal_date) AS TINYINT)          AS WeekOfYear,

    -- ── Quarter ───────────────────────────────────────────────────
    'Q-' + CAST(DATEPART(QUARTER, cal_date) AS CHAR(1))   AS QuarterName,

    'Q-' + CAST(DATEPART(QUARTER, cal_date) AS CHAR(1))
        + ',' + RIGHT(CAST(YEAR(cal_date) AS CHAR(4)), 2) AS QuarterYear,

    -- ── Fiscal Year (April start) ─────────────────────────────────
    CASE
        WHEN MONTH(cal_date) >= 4
            THEN CAST(YEAR(cal_date)     AS VARCHAR(4)) + '-'
               + CAST(YEAR(cal_date) + 1 AS VARCHAR(4))
        ELSE
              CAST(YEAR(cal_date) - 1 AS VARCHAR(4)) + '-'
            + CAST(YEAR(cal_date)     AS VARCHAR(4))
    END                                                    AS FiscalYear,

    CASE
        WHEN MONTH(cal_date) >= 4
            THEN 'FYI ' + RIGHT(CAST(YEAR(cal_date)     AS CHAR(4)), 2)
                 + '-'  + RIGHT(CAST(YEAR(cal_date) + 1 AS CHAR(4)), 2)
        ELSE
              'FYI ' + RIGHT(CAST(YEAR(cal_date) - 1 AS CHAR(4)), 2)
              + '-'   + RIGHT(CAST(YEAR(cal_date)     AS CHAR(4)), 2)
    END                                                    AS FiscalYearName,

    -- ── Leap Year ─────────────────────────────────────────────────
    CAST(
        CASE
            WHEN (YEAR(cal_date) % 4 = 0 AND YEAR(cal_date) % 100 <> 0)
              OR  YEAR(cal_date) % 400 = 0 THEN 1
            ELSE 0
        END
    AS BIT)                                                AS IsLeapYear,

    -- ── Flags ─────────────────────────────────────────────────────
    CAST(
        CASE WHEN DATEPART(WEEKDAY, cal_date) IN (1, 7) THEN 0 ELSE 1 END
    AS BIT)                                                AS IsWorkingDay,

    CAST(
        CASE WHEN DATEPART(WEEKDAY, cal_date) IN (1, 7) THEN 1 ELSE 0 END
    AS BIT)                                                AS IsHoliday,

    NULL                                                   AS HolidayName,

    CAST(
        CASE WHEN DATEPART(WEEKDAY, cal_date) IN (1, 7) THEN 0 ELSE 1 END
    AS BIT)                                                AS IsBusinessDay

FROM
(
    -- GENERATE_SERIES produces one row per day offset (0, 1, 2 … N)
    -- DATEADD converts each offset into an actual date
    SELECT DATEADD(DAY, value, @StartDate) AS cal_date
    FROM   GENERATE_SERIES(0, DATEDIFF(DAY, @StartDate, @EndDate))
) AS DateSeries;


-- ------------------------------------------------------------
-- STEP 3: Optional – mark public holidays from a reference table
-- ------------------------------------------------------------
-- UPDATE d
-- SET    d.IsHoliday     = 1,
--        d.IsBusinessDay = 0,
--        d.IsWorkingDay  = 0,
--        d.HolidayName   = h.HolidayName
-- FROM   dbo.DimDate     d
-- JOIN   dbo.HolidayList h ON d.Date = h.HolidayDate;


-- ------------------------------------------------------------
-- STEP 4: Verify
-- ------------------------------------------------------------
SELECT TOP 10 * FROM dbo.DimDate ORDER BY Date;

SELECT
    TotalRows    = COUNT(*),
    MinDate      = MIN(Date),
    MaxDate      = MAX(Date),
    Weekdays     = SUM(CAST(IsWeekDay  AS INT)),
    Weekends     = SUM(CAST(IsHoliday  AS INT)),
    LeapYearDays = SUM(CAST(IsLeapYear AS INT))
FROM dbo.DimDate;
 