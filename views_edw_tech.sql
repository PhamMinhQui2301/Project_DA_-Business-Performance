-- =============================================================================
-- EDW_Tech | TDA Fashion Retail — Complete SQL View Layer
-- Architecture: 2-Layer Star Schema (No View Chaining)
-- Author: Senior BI Design
-- Created: 2026-09-05
-- Database: EDW_Tech (SQL Server)
-- =============================================================================
--
-- LAYER 1 — DIMENSION VIEWS (v_Dim*)
--   v_DimProduct      : SKU master — product, color, size, category, collection
--   v_DimStore        : Store master — region, AM, franchise/direct
--   v_DimEmployee     : All staff — offline (MDM) + online telesales (GMC)
--   v_DimDate         : Calendar — MDM E00Calendar
--   v_DimCustomer     : Customer base — GMC (telesales has richest customer data)
--
-- LAYER 2 — FACT VIEWS (v_Fact*)
--   v_FactSales       : ALL orders, all channels — RMS + GMC + Lazada + Shopee + Tiki
--   v_FactTarget      : Monthly target — per store (RMS) + GMC + per platform (Ecom)
--
-- Power BI Star Schema relationships:
--   v_FactSales[DateKey]  → v_DimDate[DateKey]
--   v_FactSales[SKUCode]  → v_DimProduct[SKUCode]
--   v_FactSales[StoreID]  → v_DimStore[StoreID]
--   v_FactSales[EmpID]    → v_DimEmployee[EmpID]
--   v_FactTarget[DateKey] → v_DimDate[DateKey]
--   v_FactTarget[StoreID] → v_DimStore[StoreID]
--
-- =============================================================================
-- STATUS REFERENCE
--   RMS:    Status=4 → Thành công | Status=5 → Đã hủy (FunctType='O')
--   GMC:    StatusID=3 → Thành công | StatusID=4 → Đã hủy
--   Lazada: status='delivered' → Success
--   Shopee: TrangThaiDonHang LIKE '%Hoàn thành%' → Success
--   Tiki:   TrangThai LIKE '%thành công%' → Success
-- =============================================================================

USE EDW_Tech;
GO

-- ===========================================================================
-- LAYER 1: DIMENSION VIEWS
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- v_DimProduct: Product master at SKU level
-- Includes: item info, color, size, category, collection, pricing
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_DimProduct AS
SELECT
    sku.SKUCode,
    sku.ItemCode,
    mst.ItemName                                            AS ProductName,
    -- SKU attributes: attr1 = color ID, attr2 = size ID
    -- But we can also parse from SKUCode: ItemCode_Color_Size
    sku.sku_attr1                                           AS ColorCode,
    sku.sku_attr2                                           AS SizeCode,
    cat.CateName                                            AS CategoryName,
    CAST(mst.ItemCategory AS INT)                           AS CategoryID,
    mst.ItemCollection                                      AS CollectionCode,
    col.collectionName                                      AS CollectionName,
    CAST(col.collectionMonth AS TINYINT)                    AS CollectionMonth,
    CAST(col.collectionYear AS SMALLINT)                    AS CollectionYear,
    -- For date dimension join: collection as YearMonth int (YYYYMM)
    CAST(col.collectionYear AS INT) * 100
        + CAST(col.collectionMonth AS INT)                  AS CollectionYearMonth,
    sku.COGS                                                AS CostOfGoods,
    sku.SalesPrice                                          AS ListPrice,
    sku.IsActive                                            AS IsActive,
    ISNULL(mst.IsOnlyOnline, 0)                             AS IsOnlineOnly,
    mst.ProductBrand                                        AS Brand,
    sku.BarCode,
    CAST(TRY_CAST(mst.PackageWeight AS DECIMAL(10,3)) AS DECIMAL(10,3)) AS PackageWeight_kg
FROM rms.E00ItemSKUs sku
LEFT JOIN rms.E00ItemMST mst
    ON sku.ItemCode = mst.ItemCode
    AND mst.IsDelete = 0
LEFT JOIN rms.E00ItemCategory cat
    ON CAST(mst.ItemCategory AS INT) = cat.CateID
LEFT JOIN rms.E00Collection col
    ON col.collectionMonth = mst.MonthOfCollection
    AND col.collectionYear  = mst.YearOfCollection
WHERE sku.IsDelete = 0;
GO


-- ---------------------------------------------------------------------------
-- v_DimStore: Store master — offline stores only
-- Includes: store info, area manager, region, store type
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_DimStore AS
SELECT
    s.StoreID,
    s.StoreName,
    s.EmpID                                                 AS AM_EmpID,
    s.AmName                                                AS AM_Name,
    LTRIM(RTRIM(s.RegionCode))                              AS RegionCode,
    LTRIM(RTRIM(s.RegionName))                              AS RegionName,
    LTRIM(RTRIM(s.StoreType))                               AS StoreType,
    CASE WHEN LTRIM(RTRIM(s.StoreType)) = N'TRỰC THUỘC'
         THEN 'Directly Owned'
         ELSE 'Franchise' END                               AS OwnershipType,
    cs.IsFranchise,
    cs.City,
    cs.District,
    cs.Ward,
    cs.Address,
    cs.Phone
FROM rms.E00Store_AM s
LEFT JOIN mdm.E00CORStores cs
    ON cs.No_ = s.StoreID
    AND cs.IsDelete = 0;
GO


-- ---------------------------------------------------------------------------
-- v_DimEmployee: All staff — offline stores + online telesales
-- Note: emp_id in MDM, ID in GMC; unified into EmpID nvarchar for joining
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_DimEmployee AS
-- Offline staff from MDM (includes store managers and sales staff)
-- Note: BGD, IsActive, isEmp stored as nvarchar 'True'/'False' or '1'/'0'
SELECT
    e.emp_id                                                AS EmpID,
    LTRIM(RTRIM(e.emp_name))                                AS EmpName,
    e.Gender,
    CAST(e.Department AS NVARCHAR(100))                     AS Department,
    CASE WHEN CAST(e.BGD AS NVARCHAR(10)) IN ('1','True','true') THEN 'Manager' ELSE 'Staff' END AS Role,
    e.SiteID                                                AS StoreID,
    CASE WHEN CAST(e.IsActive AS NVARCHAR(10)) IN ('1','True','true') THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsActive,
    'Offline'                                               AS Channel,
    CAST(TRY_CAST(e.start_date AS DATE) AS DATE)            AS StartDate,
    CAST(TRY_CAST(e.end_date AS DATE) AS DATE)              AS EndDate
FROM mdm.E00Employee e
WHERE CAST(e.isEmp AS NVARCHAR(10)) IN ('1','True','true')

UNION ALL

-- Online sales staff from GMC telesales system
SELECT
    g.Code                                                  AS EmpID,
    LTRIM(RTRIM(g.Name))                                    AS EmpName,
    NULL                                                    AS Gender,
    CAST(g.Department AS NVARCHAR(100))                     AS Department,
    CASE WHEN TRY_CAST(g.IsLeader AS INT) = 1 THEN 'Manager' ELSE 'Staff' END AS Role,
    NULL                                                    AS StoreID,
    CAST(1 AS BIT)                                          AS IsActive,
    'Online'                                                AS Channel,
    CAST(NULL AS DATE)                                      AS StartDate,
    CAST(NULL AS DATE)                                      AS EndDate
FROM gmc.E00EmployeeOnline g;
GO


-- ---------------------------------------------------------------------------
-- v_DimDate: Calendar dimension — full date attributes
-- Source: mdm.E00Calendar (pre-built calendar table)
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_DimDate AS
SELECT
    date_key                                                AS DateKey,      -- INT YYYYMMDD
    CAST(date AS DATE)                                      AS FullDate,
    date_name                                               AS DateName,     -- Vietnamese day label
    day_of_month                                            AS DayOfMonth,
    week_of_year                                            AS WeekOfYear,
    week_number                                             AS WeekNumber,   -- 'W1','W2',...
    week_name                                               AS WeekName,
    month                                                   AS YearMonth,    -- INT YYYYMM
    CAST(month_of_year AS TINYINT)                          AS MonthNum,
    month_name                                              AS MonthName,
    quarter                                                 AS YearQuarter,  -- 'YYYY-Q#'
    quarter_name                                            AS QuarterName,  -- 'Quý 1',...
    CAST(quarter_of_year AS TINYINT)                        AS QuarterNum,
    CAST(year_name AS SMALLINT)                             AS [Year],
    CASE WHEN is_working_day = 'Y' THEN 1 ELSE 0 END        AS IsWorkingDay,
    CASE WHEN is_holiday = 'Y' THEN 1 ELSE 0 END            AS IsHoliday,
    week_start_date                                         AS WeekStartDate,
    week_end_date                                           AS WeekEndDate
FROM mdm.E00Calendar;
GO


-- ---------------------------------------------------------------------------
-- v_DimCustomer: Customer master — from GMC (richest customer attributes)
-- GMC captures customer profile: name, phone, province, gender, birthday
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_DimCustomer AS
SELECT DISTINCT
    oh.CustomerID,
    MAX(oh.CustomerName)                                    AS CustomerName,
    MAX(oh.PhoneNumber)                                     AS Phone,
    MAX(oh.CustomerGender)                                  AS Gender,
    CASE
        WHEN MAX(oh.CustomerGender) IN ('Male','male','MALE','Nam','nam')       THEN N'Nam'
        WHEN MAX(oh.CustomerGender) IN ('Female','female','FEMALE',N'Nữ',N'nữ',N'Nu',N'nu') THEN N'Nữ'
        WHEN MAX(oh.CustomerGender) IS NULL OR MAX(oh.CustomerGender) = ''      THEN N'Không xác định'
        ELSE N'Không xác định'
    END                                                     AS New_Gender,
    MAX(CAST(TRY_CAST(oh.BirthDay AS DATE) AS DATE))        AS BirthDate,
    MAX(oh.Provinces)                                       AS Province,
    MAX(CAST(TRY_CAST(oh.DistrictID AS INT) AS NVARCHAR(20))) AS DistrictID,
    MAX(CAST(TRY_CAST(oh.WardID AS INT) AS NVARCHAR(20)))   AS WardID,
    MAX(oh.Email)                                           AS Email,
    CAST(MAX(CASE WHEN CAST(oh.IsWholesaler AS NVARCHAR(10)) IN ('1','True','true') THEN 1 ELSE 0 END) AS BIT) AS IsWholesaler,
    -- Body measurements — critical for fashion size analytics
    MAX(TRY_CAST(oh.CustomerHeight AS DECIMAL(5,1)))        AS Height_cm,
    MAX(TRY_CAST(oh.CustomerWeight AS DECIMAL(5,1)))        AS Weight_kg,
    MAX(TRY_CAST(oh.CustomerWaistSize AS DECIMAL(5,1)))     AS WaistSize_cm,
    MIN(CAST(TRY_CAST(oh.CreateDate AS DATE) AS DATE))      AS FirstOrderDate,
    MAX(CAST(TRY_CAST(oh.CreateDate AS DATE) AS DATE))      AS LastOrderDate,
    COUNT(DISTINCT oh.ID)                                   AS TotalOrders
FROM gmc.E01OrderHeader oh
WHERE oh.CustomerID IS NOT NULL
  AND oh.IsDelete = 0
GROUP BY oh.CustomerID;
GO


-- ===========================================================================
-- LAYER 2: FACT VIEWS
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- v_FactSales: Unified order line items — ALL 5 channels
-- Grain : 1 row = 1 order line item (1 SKU in 1 order)
-- Revenue: NetRevenue = revenue AFTER discount, BEFORE platform fees
--          Use IsSuccess=1 to filter for actual completed revenue
-- DateKey: OrderDate (for volume tracking); SuccessDate for revenue booking
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_FactSales AS

-- ═══════════════════════════════════════════════════
-- RMS — Offline Physical Stores
-- ═══════════════════════════════════════════════════
SELECT
    oh.OrderCode                                            AS OrderID,
    CONCAT(oh.OrderCode, '_', oi.SKUCode)                   AS LineID,
    'RMS'                                                   AS Channel,
    'Offline'                                               AS ChannelGroup,
    CAST(NULL AS NVARCHAR(50))                              AS Platform,
    CONVERT(INT, CONVERT(VARCHAR(8), CAST(oh.DocDate AS DATE), 112))
                                                            AS DateKey,
    CAST(oh.DocDate AS DATE)                                AS OrderDate,
    CAST(NULL AS DATE)                                      AS SuccessDate,
    oh.SiteID                                               AS StoreID,
    oh.SalesNo                                              AS EmpID,
    oi.SKUCode,
    oh.CustID                                               AS CustomerID,
    oh.CustName                                             AS CustomerName,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerProvince,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerDistrict,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerWard,
    CAST(NULL AS NVARCHAR(100))                             AS PaymentMethod,
    CAST(oi.Qty AS INT)                                     AS Quantity,
    TRY_CAST(oi.UnitPrice AS DECIMAL(18,2))                 AS SalePrice,
    TRY_CAST(oi.StandardPrice AS DECIMAL(18,2))             AS ListPrice,
    TRY_CAST(oi.DiscItemValue AS DECIMAL(18,2))             AS DiscountAmount,
    (TRY_CAST(oi.Qty AS DECIMAL(18,2)) * TRY_CAST(oi.StandardPrice AS DECIMAL(18,2))
        - TRY_CAST(oi.DiscItemValue AS DECIMAL(18,2)))      AS GMV,
    (TRY_CAST(oi.Qty AS DECIMAL(18,2)) * TRY_CAST(oi.StandardPrice AS DECIMAL(18,2))
        - TRY_CAST(oi.DiscItemValue AS DECIMAL(18,2)))      AS NetRevenue,
    CAST(0 AS DECIMAL(18,2))                                AS PlatformFee,
    TRY_CAST(oh.ShipCost AS DECIMAL(18,2))                  AS ShippingFee,
    CAST(oh.Status AS NVARCHAR(50))                         AS StatusRaw,
    st.StatusName                                           AS StatusName,
    CAST(CASE WHEN oh.Status = 4 THEN 1 ELSE 0 END AS BIT)  AS IsSuccess,
    CAST(CASE WHEN oh.Status = 5 THEN 1 ELSE 0 END AS BIT)  AS IsCancelled,
    CAST(CASE WHEN oh.Status = 0 THEN 1 ELSE 0 END AS BIT)  AS IsUnknown,
    CAST(oh.Source AS NVARCHAR(20))                         AS SourceID,
    CAST(oh.OrderType AS NVARCHAR(50))                      AS OrderType

FROM rms.E01OrderHeader oh
JOIN rms.E01OrderItems oi
    ON  oi.OrderCode = oh.OrderCode
    AND oi.SiteID    = oh.SiteID
LEFT JOIN rms.E00Status st
    ON  st.StatusID   = oh.Status
    AND st.FunctType  = 'O'
WHERE oi.IsFreeitem = 0
  AND oi.IsExchange = 0

UNION ALL

-- ═══════════════════════════════════════════════════
-- GMC — Telesales / Social Commerce
-- ═══════════════════════════════════════════════════
SELECT
    CAST(oi.OrderID AS NVARCHAR(50))                        AS OrderID,
    CAST(oi.ID AS NVARCHAR(50))                             AS LineID,
    'GMC'                                                   AS Channel,
    'Online'                                                AS ChannelGroup,
    'GMC'                                                   AS Platform,
    CONVERT(INT, CONVERT(VARCHAR(8),
        CAST(TRY_CAST(oh.CreateDate AS DATE) AS DATE), 112)) AS DateKey,
    CAST(TRY_CAST(oh.CreateDate AS DATE) AS DATE)           AS OrderDate,
    CAST(TRY_CAST(oi.SuccessDate AS DATE) AS DATE)          AS SuccessDate,
    CAST(NULL AS NVARCHAR(20))                              AS StoreID,
    oh.AssignTo                                             AS EmpID,
    oi.ProductID                                            AS SKUCode,
    CAST(oh.CustomerID AS NVARCHAR(50))                     AS CustomerID,
    oh.CustomerName                                         AS CustomerName,
    oh.Provinces                                            AS CustomerProvince,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerDistrict,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerWard,
    CAST(oh.PaymentMethod AS NVARCHAR(100))                 AS PaymentMethod,
    TRY_CAST(oi.Quantity AS INT)                            AS Quantity,
    TRY_CAST(oi.UnitPrice AS DECIMAL(18,2))                 AS SalePrice,
    TRY_CAST(oi.OriginalPrice AS DECIMAL(18,2))             AS ListPrice,
    (TRY_CAST(oi.OriginalPrice AS DECIMAL(18,2)) - TRY_CAST(oi.UnitPrice AS DECIMAL(18,2)))
        * TRY_CAST(oi.Quantity AS DECIMAL(18,2))            AS DiscountAmount,
    TRY_CAST(oi.Total AS DECIMAL(18,2))                     AS GMV,
    TRY_CAST(oi.Total AS DECIMAL(18,2))                     AS NetRevenue,
    CAST(0 AS DECIMAL(18,2))                                AS PlatformFee,
    TRY_CAST(oh.ShipPrice AS DECIMAL(18,2))                 AS ShippingFee,
    CAST(oh.StatusID AS NVARCHAR(20))                       AS StatusRaw,
    st.Name                                                 AS StatusName,
    CAST(CASE WHEN oh.StatusID = 3 THEN 1 ELSE 0 END AS BIT) AS IsSuccess,
    CAST(CASE WHEN oh.StatusID = 4 THEN 1 ELSE 0 END AS BIT) AS IsCancelled,
    CAST(0 AS BIT)                                          AS IsUnknown,
    CAST(oh.Source AS NVARCHAR(20))                         AS SourceID,
    CAST(oh.CategoryID AS NVARCHAR(50))                     AS OrderType

FROM gmc.E01OrderHeader oh
JOIN gmc.E01OrderItemsOnline oi ON oi.OrderID = oh.ID
LEFT JOIN gmc.E00OrderStatus st ON st.ID = oh.StatusID
WHERE oh.IsDelete = 0

UNION ALL

-- ═══════════════════════════════════════════════════
-- ECOM — Lazada
-- ═══════════════════════════════════════════════════
SELECT
    CAST(orderNumber AS NVARCHAR(50))                       AS OrderID,
    CAST(orderItemId AS NVARCHAR(50))                       AS LineID,
    'Lazada'                                                AS Channel,
    'Ecom'                                                  AS ChannelGroup,
    'Lazada'                                                AS Platform,
    CONVERT(INT, CONVERT(VARCHAR(8),
        CAST(TRY_CAST(createTime AS DATE) AS DATE), 112))   AS DateKey,
    CAST(TRY_CAST(createTime AS DATE) AS DATE)              AS OrderDate,
    CAST(TRY_CAST(deliveredDate AS DATE) AS DATE)           AS SuccessDate,
    CAST(NULL AS NVARCHAR(20))                              AS StoreID,
    CAST(NULL AS NVARCHAR(50))                              AS EmpID,
    sellerSku                                               AS SKUCode,
    CAST(NULL AS NVARCHAR(50))                              AS CustomerID,
    customerName                                            AS CustomerName,
    shippingCity                                            AS CustomerProvince,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerDistrict,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerWard,
    payMethod                                               AS PaymentMethod,
    CAST(1 AS INT)                                          AS Quantity,
    TRY_CAST(paidPrice AS DECIMAL(18,2))                    AS SalePrice,
    TRY_CAST(unitPrice AS DECIMAL(18,2))                    AS ListPrice,
    TRY_CAST(ABS(ISNULL(sellerDiscountTotal,0)) AS DECIMAL(18,2)) AS DiscountAmount,
    TRY_CAST(paidPrice AS DECIMAL(18,2))                    AS GMV,
    TRY_CAST(paidPrice AS DECIMAL(18,2))                    AS NetRevenue,
    CAST(0 AS DECIMAL(18,2))                                AS PlatformFee,
    TRY_CAST(ISNULL(shippingFee,0) AS DECIMAL(18,2))        AS ShippingFee,
    [status]                                                AS StatusRaw,
    [status]                                                AS StatusName,
    CAST(CASE WHEN [status] = 'delivered' THEN 1 ELSE 0 END AS BIT) AS IsSuccess,
    CAST(CASE WHEN [status] LIKE '%cancel%'
               OR [status] LIKE '%return%' THEN 1 ELSE 0 END AS BIT) AS IsCancelled,
    CAST(0 AS BIT)                                          AS IsUnknown,
    'Lazada'                                                AS SourceID,
    orderType                                               AS OrderType

FROM ecom.E01LazadaOrders

UNION ALL

-- ═══════════════════════════════════════════════════
-- ECOM — Shopee
-- NetRevenue = GMV - PhiCoDinh - PhiDichVu - PhiThanhToan
-- ═══════════════════════════════════════════════════
SELECT
    MaDonHang                                               AS OrderID,
    CAST(Id AS NVARCHAR(50))                                AS LineID,
    'Shopee'                                                AS Channel,
    'Ecom'                                                  AS ChannelGroup,
    'Shopee'                                                AS Platform,
    CONVERT(INT, CONVERT(VARCHAR(8),
        CAST(TRY_CAST(NgayDatHang AS DATE) AS DATE), 112))  AS DateKey,
    CAST(TRY_CAST(NgayDatHang AS DATE) AS DATE)             AS OrderDate,
    CAST(TRY_CAST(ThoiGianHoanThanhDonHang AS DATE) AS DATE) AS SuccessDate,
    CAST(NULL AS NVARCHAR(20))                              AS StoreID,
    CAST(NULL AS NVARCHAR(50))                              AS EmpID,
    SKUSanPham                                              AS SKUCode,
    CAST(NULL AS NVARCHAR(50))                              AS CustomerID,
    TenNguoiNhan                                            AS CustomerName,
    TinhThanhPho                                            AS CustomerProvince,
    QuanHuyen                                               AS CustomerDistrict,
    PhuongXa                                                AS CustomerWard,
    PhuongThucThanhToan                                     AS PaymentMethod,
    TRY_CAST(SoLuong AS INT)                                AS Quantity,
    TRY_CAST(GiaUuDai AS DECIMAL(18,2))                     AS SalePrice,
    TRY_CAST(GiaGoc AS DECIMAL(18,2))                       AS ListPrice,
    CASE WHEN TRY_CAST(GiaGoc AS DECIMAL(18,2)) > 0
         THEN (TRY_CAST(GiaGoc AS DECIMAL(18,2)) - TRY_CAST(GiaUuDai AS DECIMAL(18,2)))
              * TRY_CAST(SoLuong AS DECIMAL(18,2))
         ELSE 0 END                                         AS DiscountAmount,
    TRY_CAST(TongGiaBanSanPham AS DECIMAL(18,2))            AS GMV,
    -- NetRevenue = GMV - platform fees (cố định + dịch vụ + thanh toán)
    (TRY_CAST(TongGiaBanSanPham AS DECIMAL(18,2))
        - ISNULL(TRY_CAST(PhiCoDinh AS DECIMAL(18,2)), 0)
        - ISNULL(TRY_CAST(PhiDichVu AS DECIMAL(18,2)), 0)
        - ISNULL(TRY_CAST(PhiThanhToan AS DECIMAL(18,2)), 0))
                                                            AS NetRevenue,
    (ISNULL(TRY_CAST(PhiCoDinh AS DECIMAL(18,2)), 0)
        + ISNULL(TRY_CAST(PhiDichVu AS DECIMAL(18,2)), 0)
        + ISNULL(TRY_CAST(PhiThanhToan AS DECIMAL(18,2)), 0))
                                                            AS PlatformFee,
    ISNULL(TRY_CAST(PhiVanChuyenDuKien AS DECIMAL(18,2)), 0) AS ShippingFee,
    TrangThaiDonHang                                        AS StatusRaw,
    TrangThaiDonHang                                        AS StatusName,
    CAST(CASE WHEN TrangThaiDonHang LIKE N'%Hoàn thành%'
               OR TrangThaiDonHang LIKE N'%hoàn tất%' THEN 1 ELSE 0 END AS BIT) AS IsSuccess,
    CAST(CASE WHEN TrangThaiDonHang LIKE N'%Hủy%'
               OR TrangThaiDonHang LIKE N'%huỷ%' THEN 1 ELSE 0 END AS BIT) AS IsCancelled,
    CAST(0 AS BIT)                                          AS IsUnknown,
    'Shopee'                                                AS SourceID,
    LoaiDonHang                                             AS OrderType

FROM ecom.E01ShopeeOrders

UNION ALL

-- ═══════════════════════════════════════════════════
-- ECOM — Tiki
-- DoanhThu = net revenue sau khi Tiki đã trừ phí
-- ═══════════════════════════════════════════════════
SELECT
    MaDonHang                                               AS OrderID,
    CAST(Id AS NVARCHAR(50))                                AS LineID,
    'Tiki'                                                  AS Channel,
    'Ecom'                                                  AS ChannelGroup,
    'Tiki'                                                  AS Platform,
    CONVERT(INT, CONVERT(VARCHAR(8),
        CAST(TRY_CAST(NgayDat AS DATE) AS DATE), 112))      AS DateKey,
    CAST(TRY_CAST(NgayDat AS DATE) AS DATE)                 AS OrderDate,
    CAST(TRY_CAST(NgayGiaoHangThanhCong AS DATE) AS DATE)   AS SuccessDate,
    CAST(NULL AS NVARCHAR(20))                              AS StoreID,
    CAST(NULL AS NVARCHAR(50))                              AS EmpID,
    SSKU                                                    AS SKUCode,
    CAST(NULL AS NVARCHAR(50))                              AS CustomerID,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerName,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerProvince,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerDistrict,
    CAST(NULL AS NVARCHAR(100))                             AS CustomerWard,
    PhuongThucThanhToan                                     AS PaymentMethod,
    TRY_CAST(SLBan AS INT)                                  AS Quantity,
    TRY_CAST(DonGia AS DECIMAL(18,2))                       AS SalePrice,
    TRY_CAST(DonGia AS DECIMAL(18,2))                       AS ListPrice,
    CASE WHEN TRY_CAST(DonGia AS DECIMAL(18,2)) > 0 AND TRY_CAST(SLBan AS INT) > 0
         THEN (TRY_CAST(DonGia AS DECIMAL(18,2)) * TRY_CAST(SLBan AS DECIMAL(18,2)))
              - TRY_CAST(DoanhThu AS DECIMAL(18,2))
         ELSE 0 END                                         AS DiscountAmount,
    (TRY_CAST(DonGia AS DECIMAL(18,2)) * TRY_CAST(SLBan AS DECIMAL(18,2)))
                                                            AS GMV,
    TRY_CAST(DoanhThu AS DECIMAL(18,2))                     AS NetRevenue,
    ISNULL(TRY_CAST(PhiPhaiTraTiki AS DECIMAL(18,2)), 0)    AS PlatformFee,
    CAST(0 AS DECIMAL(18,2))                                AS ShippingFee,
    TrangThai                                               AS StatusRaw,
    TrangThai                                               AS StatusName,
    CAST(CASE WHEN TrangThai LIKE N'%thành công%'
               OR TrangThai LIKE N'%Giao hàng thành công%' THEN 1 ELSE 0 END AS BIT) AS IsSuccess,
    CAST(CASE WHEN TrangThai LIKE N'%Hủy%'
               OR TrangThai LIKE N'%huỷ%' THEN 1 ELSE 0 END AS BIT) AS IsCancelled,
    CAST(0 AS BIT)                                          AS IsUnknown,
    'Tiki'                                                  AS SourceID,
    CAST(NULL AS NVARCHAR(50))                              AS OrderType

FROM ecom.E01TikiOrders;
GO


-- ---------------------------------------------------------------------------
-- v_FactTarget: Monthly targets — unified across all channels
-- Grain: 1 row = 1 store (or channel) per month
-- DateKey: YYYYMMDD of the 1st day of the month
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_FactTarget AS

-- RMS: per store per month
SELECT
    CAST(t.Datekey AS INT)                                  AS DateKey,
    t.StoreId                                               AS StoreID,
    LTRIM(RTRIM(t.StoreName))                               AS StoreName,
    LTRIM(RTRIM(t.Region))                                  AS RegionName,
    LTRIM(RTRIM(t.StoreType))                               AS StoreType,
    LTRIM(RTRIM(t.AM))                                      AS AM_Name,
    'RMS'                                                   AS Channel,
    'Offline'                                               AS ChannelGroup,
    CAST(NULL AS NVARCHAR(50))                              AS Platform,
    t.Target                                                AS TargetRevenue,
    CAST(NULL AS DECIMAL(18,2))                             AS TargetAOV,
    CAST(NULL AS INT)                                       AS TargetOrders,
    CAST(NULL AS INT)                                       AS TargetItems

FROM rms.E00TargetStores t

UNION ALL

-- GMC: monthly total online target — includes AOV, Orders, Items targets
SELECT
    CAST(t.DateKey AS INT)                                  AS DateKey,
    CAST(NULL AS NVARCHAR(20))                              AS StoreID,
    N'GMC Telesales'                                        AS StoreName,
    CAST(NULL AS NVARCHAR(50))                              AS RegionName,
    CAST(NULL AS NVARCHAR(50))                              AS StoreType,
    CAST(NULL AS NVARCHAR(100))                             AS AM_Name,
    'GMC'                                                   AS Channel,
    'Online'                                                AS ChannelGroup,
    CAST(NULL AS NVARCHAR(50))                              AS Platform,
    t.Target                                                AS TargetRevenue,
    TRY_CAST(t.AOV AS DECIMAL(18,2))                        AS TargetAOV,
    TRY_CAST(t.Orders AS INT)                               AS TargetOrders,
    TRY_CAST(t.Items AS INT)                                AS TargetItems

FROM gmc.E00Target t

UNION ALL

-- ECOM: per platform per month
SELECT
    CAST(t.DateKey AS INT)                                  AS DateKey,
    CAST(NULL AS NVARCHAR(20))                              AS StoreID,
    t.Platform                                              AS StoreName,
    CAST(NULL AS NVARCHAR(50))                              AS RegionName,
    CAST(NULL AS NVARCHAR(50))                              AS StoreType,
    CAST(NULL AS NVARCHAR(100))                             AS AM_Name,
    'Ecom'                                                  AS Channel,
    'Ecom'                                                  AS ChannelGroup,
    t.Platform                                              AS Platform,
    t.TargetGMV                                             AS TargetRevenue,
    CAST(NULL AS DECIMAL(18,2))                             AS TargetAOV,
    CAST(NULL AS INT)                                       AS TargetOrders,
    CAST(NULL AS INT)                                       AS TargetItems

FROM ecom.E00Target t;
GO


-- ---------------------------------------------------------------------------
-- v_CustomerRFM: RFM segmentation — per customer, based on completed orders
-- R = days since last order (lower = more recent = better)
-- F = distinct order count (higher = more frequent = better)
-- M = total net revenue (higher = more valuable = better)
-- Score 1-5 via NTILE, combined into RFM_Score → Segment label
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW dbo.v_CustomerRFM AS
WITH base AS (
    SELECT
        fs.CustomerID,
        DATEDIFF(DAY, MAX(dd.FullDate), (SELECT MAX(FullDate) FROM dbo.v_DimDate)) AS Recency_Days,
        COUNT(DISTINCT fs.OrderID)                                                   AS Frequency,
        SUM(fs.NetRevenue)                                                           AS Monetary
    FROM dbo.v_FactSales fs
    JOIN dbo.v_DimDate dd ON dd.DateKey = fs.DateKey
    WHERE fs.IsSuccess = 1
      AND fs.CustomerID IS NOT NULL
    GROUP BY fs.CustomerID
),
scored AS (
    SELECT
        CustomerID,
        Recency_Days,
        Frequency,
        Monetary,
        -- R score: NTILE reversed (lower recency = higher score)
        6 - NTILE(5) OVER (ORDER BY Recency_Days ASC)  AS R_Score,
        NTILE(5) OVER (ORDER BY Frequency ASC)          AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary ASC)           AS M_Score
    FROM base
)
SELECT
    CustomerID,
    Recency_Days,
    Frequency,
    Monetary,
    R_Score,
    F_Score,
    M_Score,
    CAST(R_Score AS NVARCHAR(1)) + CAST(F_Score AS NVARCHAR(1)) + CAST(M_Score AS NVARCHAR(1)) AS RFM_Score,
    CASE
        WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 4 THEN 'Champion'
        WHEN R_Score >= 3 AND F_Score >= 3 AND M_Score >= 3 THEN 'Loyal'
        WHEN R_Score >= 4 AND F_Score <= 2                  THEN 'New Customer'
        WHEN R_Score >= 3 AND F_Score >= 2 AND M_Score >= 3 THEN 'Potential Loyalist'
        WHEN R_Score <= 2 AND F_Score >= 3 AND M_Score >= 3 THEN 'At Risk'
        WHEN R_Score = 1  AND F_Score >= 3                  THEN 'Lost Champion'
        WHEN R_Score <= 2 AND F_Score <= 2                  THEN 'Lost'
        ELSE 'Need Attention'
    END AS RFM_Segment
FROM scored;
GO


-- ===========================================================================
-- VERIFICATION QUERIES
-- Run these after creating views to validate row counts & sample data
-- ===========================================================================
/*
-- Row counts
SELECT 'v_DimProduct'   AS ViewName, COUNT(*) AS Rows FROM dbo.v_DimProduct  UNION ALL
SELECT 'v_DimStore',              COUNT(*) FROM dbo.v_DimStore      UNION ALL
SELECT 'v_DimEmployee',           COUNT(*) FROM dbo.v_DimEmployee   UNION ALL
SELECT 'v_DimDate',               COUNT(*) FROM dbo.v_DimDate       UNION ALL
SELECT 'v_DimCustomer',           COUNT(*) FROM dbo.v_DimCustomer   UNION ALL
SELECT 'v_FactSales',             COUNT(*) FROM dbo.v_FactSales      UNION ALL
SELECT 'v_FactTarget',            COUNT(*) FROM dbo.v_FactTarget;

-- Channel breakdown
SELECT Channel, ChannelGroup,
       COUNT(DISTINCT OrderID)  AS Orders,
       SUM(Quantity)            AS Units,
       SUM(CASE WHEN IsSuccess=1 THEN NetRevenue ELSE 0 END) AS Revenue_Success,
       AVG(CASE WHEN IsSuccess=1 THEN NetRevenue ELSE NULL END) AS AvgLineRevenue,
       SUM(CAST(IsSuccess AS INT)) * 100.0 / COUNT(*) AS SuccessRate_Pct
FROM dbo.v_FactSales
GROUP BY Channel, ChannelGroup
ORDER BY Revenue_Success DESC;

-- Top 10 products by revenue (successful orders)
SELECT TOP 10
    fs.SKUCode,
    p.ProductName,
    p.CategoryName,
    p.CollectionName,
    SUM(fs.Quantity)    AS TotalUnits,
    SUM(fs.NetRevenue)  AS TotalRevenue
FROM dbo.v_FactSales fs
LEFT JOIN dbo.v_DimProduct p ON p.SKUCode = fs.SKUCode
WHERE fs.IsSuccess = 1
GROUP BY fs.SKUCode, p.ProductName, p.CategoryName, p.CollectionName
ORDER BY TotalRevenue DESC;

-- Revenue vs Target by channel/month
SELECT
    t.DateKey / 100                                AS YearMonth,
    t.Channel,
    t.ChannelGroup,
    SUM(t.TargetRevenue)                           AS Target,
    SUM(CASE WHEN fs.IsSuccess=1 THEN fs.NetRevenue ELSE 0 END) AS Actual
FROM dbo.v_FactTarget t
LEFT JOIN dbo.v_FactSales fs
    ON  fs.DateKey / 100 = t.DateKey / 100
    AND fs.Channel        = t.Channel
    AND (t.StoreID IS NULL OR fs.StoreID = t.StoreID)
GROUP BY t.DateKey / 100, t.Channel, t.ChannelGroup
ORDER BY YearMonth, Channel;
*/


