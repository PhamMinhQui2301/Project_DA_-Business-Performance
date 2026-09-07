# EDW Tech — Business Performance Dashboard

> End-to-end BI project: từ 9.4GB SQL Server raw data đến public Power BI dashboard và báo cáo phân tích chuyên sâu.

**Doanh nghiệp:** GUMAC/TDA — thời trang nữ Việt Nam · 50 cửa hàng · 5 kênh phân phối · dữ liệu 10 năm (2015–2025)

## 🔗 Live Demo

| Link | Mô tả |
|---|---|
| [📊 Power BI Dashboard](https://app.powerbi.com/view?r=eyJrIjoiZDk5YTNkNjgtMjcyNC00NGU2LTg5MWItYTFmMmRhOTM0ODdkIiwidCI6IjZhYzJhZDA2LTY5MmMtNDY2My1iN2FmLWE5ZmYyYTg2NmQwYyIsImMiOjEwfQ%3D%3D) | Dashboard 5 trang: Revenue, Sales, Product, Customer RFM, Store & AM |
| [🎯 Project Pitch](https://project-da-business-performance.vercel.app/) | 8-slide giới thiệu dự án — kiến trúc, star schema, key insights |
| [📝 Báo cáo phân tích](https://project-da-business-performance.vercel.app/report/) | Phân tích chuyên sâu — nguyên nhân gốc rễ, RFM, khuyến nghị hành động |

---

## Tổng quan dự án

| Hạng mục | Chi tiết |
|---|---|
| Nguồn dữ liệu | SQL Server `.bak` · 9.4 GB · 4.36M order line items |
| Khách hàng | 607K customers |
| Kênh bán | Offline (RMS) · Telesales (GMC) · Shopee · Lazada · Tiki · TikTok |
| Mô hình dữ liệu | Star Schema · 2 Fact + 5 Dimension + 1 RFM Analytics View |
| DAX Measures | 50+ measures (Revenue, Time Intelligence, RFM, Store KPI) |
| Dashboard | 5 trang Power BI (Overview, Sales, Product, Customer RFM, Store & AM) |

## Câu hỏi phân tích

- **Revenue & Target** — Doanh thu thực tế vs kế hoạch theo kênh, vùng, thời gian?
- **Channel Performance** — Kênh nào hiệu quả nhất sau khi trừ phí nền tảng?
- **Product Analysis** — SKU / Category nào dẫn đầu doanh số?
- **Store & AM** — Cửa hàng và Account Manager nào vượt target?
- **Customer RFM** — Phân khúc Champion, Loyal, At Risk chiếm tỉ lệ bao nhiêu?
- **Order Quality** — Tỉ lệ hủy đơn, hoàn trả theo kênh?

## Kiến trúc

```
RMS · GMC · Shopee · Lazada · Tiki
            ↓
      SQL Server EDW
   (7 Views · Star Schema)
            ↓
     Power BI Desktop
   (50+ DAX · 5 Pages)
            ↓
    Public Dashboard + Web
```

## SQL Views

| View | Mô tả |
|---|---|
| `v_FactSales` | Giao dịch bán hàng · 4.36M rows |
| `v_FactTarget` | Kế hoạch doanh thu theo tháng × store |
| `v_DimDate` | Date dimension · Time Intelligence |
| `v_DimProduct` | Sản phẩm · SKU · Category |
| `v_DimStore` | 50 cửa hàng · Directly Owned / Franchise |
| `v_DimEmployee` | Nhân viên · Account Manager |
| `v_DimCustomer` | 607K khách hàng · Gender chuẩn hoá |
| `v_CustomerRFM` | RFM segmentation · NTILE(5) scoring |

## Phát hiện chính

- HCM chiếm 28% tổng doanh thu (247 tỷ), Miền Tây 82 tỷ
- 88.9% khách hàng là nữ — đúng định vị thương hiệu
- Offline chiếm ~80% revenue; Shopee cancel rate 35.5%
- Champion avg monetary = 4.28M, gấp 10× nhóm Lost
- Tất cả vùng miền vượt target 135% — target cần được recalibrate
- Tiki lưu PlatformFee âm trong DB → cần chuẩn hoá ABS()

## Tech Stack

`SQL Server 2022` · `T-SQL / Views` · `Power BI Desktop` · `DAX` · `RFM Analytics` · `Power BI MCP API` · `Vercel`

## Web

- [Pitch Deck](./pitch/index.html) — Giới thiệu dự án
- [Báo cáo phân tích](./report/index.html) — Phân tích chuyên sâu, nguyên nhân gốc rễ, khuyến nghị

---

**Phạm Minh Quí** · Data Engineering Portfolio · 2025
