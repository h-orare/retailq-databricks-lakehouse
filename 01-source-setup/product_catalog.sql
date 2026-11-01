-- =========================================================
-- RetailQ — PostgreSQL source table: product_catalog
-- Host: Neon (free tier)
-- Ingested to bronze via Lakeflow Connect (managed connector)
-- =========================================================

DROP TABLE IF EXISTS product_catalog;

CREATE TABLE product_catalog (
    product_id          VARCHAR(20) PRIMARY KEY,
    product_name        VARCHAR(200),
    category            VARCHAR(100),
    subcategory         VARCHAR(100),
    brand               VARCHAR(100),
    unit_price          NUMERIC(10,2),
    supplier_name       VARCHAR(200),
    launch_date         DATE,
    is_active           BOOLEAN,
    updated_at          TIMESTAMP
);

-- =========================================================
-- VALID ROWS
-- =========================================================

INSERT INTO product_catalog (
    product_id, product_name, category, subcategory, brand,
    unit_price, supplier_name, launch_date, is_active, updated_at
)
VALUES
('P0001','iPhone 15','Electronics','Mobile','Apple',79999,'Apple India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0002','Galaxy S24','Electronics','Mobile','Samsung',69999,'Samsung India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0003','AirPods Pro','Electronics','Accessories','Apple',24999,'Apple India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0004','Dell XPS 13','Electronics','Laptop','Dell',119999,'Dell India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0005','Sony Bravia 55','Electronics','TV','Sony',94999,'Sony India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0006','Nike Running Shoes','Fashion','Footwear','Nike',5999,'Nike India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0007','Adidas Hoodie','Fashion','Clothing','Adidas',3999,'Adidas India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0008','Puma Track Pants','Fashion','Clothing','Puma',2999,'Puma India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0009','Amul Butter','Groceries','Dairy','Amul',299,'Amul India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0010','Nestle Coffee','Groceries','Beverages','Nestle',499,'Nestle India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0011','Philips Air Fryer','Home','Kitchen','Philips',8999,'Philips India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0012','Ikea Dining Table','Home','Furniture','Ikea',15999,'Ikea India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0013','HP Pavilion Laptop','Electronics','Laptop','HP',74999,'HP India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0014','Samsung Smart TV','Electronics','TV','Samsung',84999,'Samsung India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0015','Apple Watch','Electronics','Accessories','Apple',42999,'Apple India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0016','Sony Headphones','Electronics','Accessories','Sony',12999,'Sony India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0017','Nike Sports T-Shirt','Fashion','Clothing','Nike',1999,'Nike India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0018','Puma Sneakers','Fashion','Footwear','Puma',4999,'Puma India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0019','Nestle Chocolate Pack','Groceries','Snacks','Nestle',199,'Nestle India','2025-01-01',TRUE,'2026-01-01 10:00:00'),
('P0020','Ikea Office Chair','Home','Furniture','Ikea',9999,'Ikea India','2025-01-01',TRUE,'2026-01-01 10:00:00');

-- =========================================================
-- DELIBERATELY BAD ROWS — fuel for the silver-layer
-- data quality expectations built in section 7.
--
-- The column list is written out explicitly. That is what
-- prevents the positional mismatch that broke the original
-- script (a timestamp landing in the boolean column).
--
-- product_id cannot be NULL or numeric here: it is the
-- PRIMARY KEY and the column is VARCHAR. Defects are placed
-- in non-key columns instead.
-- =========================================================

INSERT INTO product_catalog (
    product_id, product_name, category, subcategory, brand,
    unit_price, supplier_name, launch_date, is_active, updated_at
)
VALUES
-- missing product name
('P9991', NULL,                'Fashion',         'Shoes', 'BrandY',  2000, 'SupplierY', '2024-01-01', TRUE, CURRENT_TIMESTAMP),
-- category outside the allowed set
('P9992', 'Invalid Product B', 'InvalidCategory', 'Misc',  'BrandZ',  5000, 'SupplierZ', '2024-01-01', TRUE, CURRENT_TIMESTAMP),
-- negative price
('P9993', 'Invalid Product C', 'Home',            'Decor', 'BrandA',  -100, 'SupplierA', '2024-01-01', TRUE, CURRENT_TIMESTAMP),
-- missing category
('P9994', 'Invalid Product D', NULL,              'Misc',  'BrandB',  1000, 'SupplierB', '2024-01-01', TRUE, CURRENT_TIMESTAMP);

-- =========================================================
-- VERIFY
-- =========================================================
-- Expect 24 rows: 20 valid + 4 deliberately bad
SELECT COUNT(*) AS total_rows FROM product_catalog;

SELECT product_id, product_name, category, unit_price
FROM product_catalog
WHERE product_name IS NULL
   OR category IS NULL
   OR category NOT IN ('Electronics','Fashion','Groceries','Home')
   OR unit_price < 0;
