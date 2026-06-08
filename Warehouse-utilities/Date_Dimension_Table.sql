-- ============================================================
-- DATE DIMENSION - Microsoft Fabric Warehouse (T-SQL)
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
-- STEP 2: Populate using cross-join number generator
--         (No recursive CTE → no MAXRECURSION hint needed)
-- ------------------------------------------------------------
DECLARE @StartDate DATE = '2025-01-01';
DECLARE @EndDate   DATE = '2035-12-31';
DECLARE @TotalDays INT  = DATEDIFF(DAY, @StartDate, @EndDate) + 1;  -- 4018 days

WITH
N10 AS (
    -- 10 rows: 0–9
    SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
),
N100 AS (
    -- 100 rows: 10 × 10
    SELECT a.n * 10 + b.n AS n
    FROM N10 a CROSS JOIN N10 b
),
N10000 AS (
    -- 10,000 rows: 100 × 100  →  covers any range up to ~27 years
    SELECT a.n * 100 + b.n AS n
    FROM N100 a CROSS JOIN N100 b
),
DateSeries AS (
    -- Convert numbers to dates, trim to exact range
    SELECT DATEADD(DAY, n, @StartDate) AS cal_date
    FROM   N10000
    WHERE  n < @TotalDays
)
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
    CONVERT(CHAR(8), cal_date, 112)                        AS Date_ID,   -- yyyyMMdd

    -- ── Day ──────────────────────────────────────────────────────
    CAST(DAY(cal_date) AS TINYINT)                         AS DayOfMonth,

    -- Spark date_format(d,'E') → 3-letter day abbreviation
    LEFT(DATENAME(WEEKDAY, cal_date), 3)                   AS DayName,

    -- Spark dayofweek(): 1=Sun … 7=Sat
    CAST(DATEPART(WEEKDAY, cal_date) AS TINYINT)           AS DayOfWeek,

    -- IsWeekDay: false when Sun(1) or Sat(7)
    CAST(
        CASE WHEN DATEPART(WEEKDAY, cal_date) IN (1, 7) THEN 0 ELSE 1 END
    AS BIT)                                                AS IsWeekDay,

    -- ── Month / Week ─────────────────────────────────────────────
    CAST(MONTH(cal_date) AS TINYINT)                       AS Month,

    -- Spark: ceil(day / 7.0)
    CAST(CEILING(DAY(cal_date) / 7.0) AS TINYINT)         AS WeekOfMonth,

    CAST(YEAR(cal_date) AS SMALLINT)                       AS Year,

    -- Spark weekofyear() → ISO week number
    CAST(DATEPART(ISO_WEEK, cal_date) AS TINYINT)          AS WeekOfYear,

    -- ── Quarter ───────────────────────────────────────────────────
    -- Spark: concat('Q-', quarter(cal_date))
    'Q-' + CAST(DATEPART(QUARTER, cal_date) AS CHAR(1))   AS QuarterName,

    -- Spark: concat('Q-', quarter(cal_date), ',', yy)
    'Q-' + CAST(DATEPART(QUARTER, cal_date) AS CHAR(1))
        + ',' + RIGHT(CAST(YEAR(cal_date) AS CHAR(4)), 2) AS QuarterYear,

    -- ── Fiscal Year (April start) ─────────────────────────────────
    -- Spark: month >= 4 → 'YYYY-YYYY+1'  else  'YYYY-1-YYYY'
    CASE
        WHEN MONTH(cal_date) >= 4
            THEN CAST(YEAR(cal_date)     AS VARCHAR(4)) + '-'
               + CAST(YEAR(cal_date) + 1 AS VARCHAR(4))
        ELSE
              CAST(YEAR(cal_date) - 1 AS VARCHAR(4)) + '-'
            + CAST(YEAR(cal_date)     AS VARCHAR(4))
    END                                                    AS FiscalYear,

    -- Spark: 'FYI YY-YY'  (2-digit years)
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

    -- ── Working / Holiday / Business Day flags ────────────────────
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

FROM DateSeries;


-- ------------------------------------------------------------
-- STEP 3: Optional – mark public holidays from a reference table
-- ------------------------------------------------------------
-- Once you maintain a dbo.HolidayList (HolidayDate, HolidayName):
--
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