-- ---------- 1. OperatorSettlementRate ----------
CREATE TABLE dbo.OperatorSettlementRate (
    rate_id        BIGINT IDENTITY(1,1) NOT NULL,
    operator_id    VARCHAR(20)  NULL,
    station_id     VARCHAR(20)  NULL,
    platform_rate  DECIMAL(7,6) NOT NULL,
    effective_from DATETIME2(3) NOT NULL,
    effective_to   DATETIME2(3) NULL,
    status         VARCHAR(20)  NOT NULL,
    created_at     DATETIME2(3) NOT NULL CONSTRAINT DF_OperatorSettlementRate_created DEFAULT SYSDATETIME(),
    updated_at     DATETIME2(3) NOT NULL CONSTRAINT DF_OperatorSettlementRate_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_OperatorSettlementRate PRIMARY KEY (rate_id),
    CONSTRAINT CK_OperatorSettlementRate_rate CHECK (platform_rate BETWEEN 0 AND 1),
    CONSTRAINT CK_OperatorSettlementRate_status CHECK (status IN ('ACTIVE','INACTIVE')),
    CONSTRAINT CK_OperatorSettlementRate_to CHECK (effective_to IS NULL OR effective_to > effective_from),
    CONSTRAINT CK_OperatorSettlementRate_oneof CHECK (
        (operator_id IS NOT NULL AND station_id IS NULL)
        OR
        (operator_id IS NULL AND station_id IS NOT NULL)
    )
);

-- ---------- 2. SettlementStatement ----------
CREATE TABLE dbo.SettlementStatement (
    settlement_id          BIGINT IDENTITY(1,1) NOT NULL,
    station_id             VARCHAR(20)  NOT NULL,
    period_month           CHAR(6)      NOT NULL,
    platform_rate          DECIMAL(7,6) NOT NULL,
    adjustment_amount      DECIMAL(18,2) NOT NULL CONSTRAINT DF_SettlementStatement_adj DEFAULT 0,
    status                 TINYINT      NOT NULL CONSTRAINT DF_SettlementStatement_status DEFAULT 0,
    assigned_account_id    BIGINT       NOT NULL,
    created_by             BIGINT       NOT NULL,
    created_at             DATETIME2(3) NOT NULL CONSTRAINT DF_SettlementStatement_created DEFAULT SYSDATETIME(),
    confirmation_evidence  NVARCHAR(500) NULL,
    confirmed_by           BIGINT       NULL,
    confirmed_at           DATETIME2(3) NULL,
    completed_at           DATETIME2(3) NULL,
    CONSTRAINT PK_SettlementStatement PRIMARY KEY (settlement_id),
    CONSTRAINT CK_SettlementStatement_rate CHECK (platform_rate BETWEEN 0 AND 1),
    CONSTRAINT CK_SettlementStatement_status CHECK (status BETWEEN 0 AND 3),
    CONSTRAINT CK_SettlementStatement_confirm CHECK (confirmed_at IS NULL OR confirmed_at >= created_at)
);

-- ---------- 3. SettlementDetail ----------
CREATE TABLE dbo.SettlementDetail (
    detail_id              BIGINT IDENTITY(1,1) NOT NULL,
    settlement_id          BIGINT       NOT NULL,
    order_id               BIGINT       NOT NULL,
    ended_at_snapshot      DATETIME2(3) NOT NULL,
    energy_snapshot        DECIMAL(10,3) NOT NULL,
    electricity_base       DECIMAL(12,2) NOT NULL,
    service_base           DECIMAL(12,2) NOT NULL,
    minimum_adjustment     DECIMAL(12,2) NOT NULL CONSTRAINT DF_SettlementDetail_adj DEFAULT 0,
    created_at             DATETIME2(3) NOT NULL CONSTRAINT DF_SettlementDetail_created DEFAULT SYSDATETIME(),
    settled_at_snapshot    DATETIME2(3) NOT NULL,
    settlement_source      VARCHAR(20)  NOT NULL,
    eligibility_checked_at DATETIME2(3) NOT NULL,
    refund_state_snapshot  VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_SettlementDetail PRIMARY KEY (detail_id),
    CONSTRAINT CK_SettlementDetail_energy CHECK (energy_snapshot >= 0),
    CONSTRAINT CK_SettlementDetail_elec CHECK (electricity_base >= 0),
    CONSTRAINT CK_SettlementDetail_svc CHECK (service_base >= 0),
    CONSTRAINT CK_SettlementDetail_min CHECK (minimum_adjustment >= 0),
    CONSTRAINT CK_SettlementDetail_source CHECK (settlement_source IN ('PERSONAL','ENTERPRISE')),
    CONSTRAINT CK_SettlementDetail_refund CHECK (refund_state_snapshot IN ('NONE','FAILED_CANCELLED'))
);

-- ---------- 4. ReconciliationDifference ----------
CREATE TABLE dbo.ReconciliationDifference (
    difference_id      BIGINT IDENTITY(1,1) NOT NULL,
    settlement_id      BIGINT       NOT NULL,
    order_id           BIGINT       NOT NULL,
    difference_type    TINYINT      NOT NULL,
    difference_amount  DECIMAL(12,2) NOT NULL,
    resolution         NVARCHAR(500) NULL,
    status             TINYINT      NOT NULL CONSTRAINT DF_ReconciliationDifference_status DEFAULT 0,
    operator_evidence  NVARCHAR(500) NULL,
    created_by         BIGINT       NOT NULL,
    created_at         DATETIME2(3) NOT NULL CONSTRAINT DF_ReconciliationDifference_created DEFAULT SYSDATETIME(),
    reviewed_by        BIGINT       NULL,
    reviewed_at        DATETIME2(3) NULL,
    refund_id          BIGINT       NULL,
    CONSTRAINT PK_ReconciliationDifference PRIMARY KEY (difference_id),
    CONSTRAINT CK_ReconciliationDifference_type CHECK (difference_type BETWEEN 1 AND 4),
    CONSTRAINT CK_ReconciliationDifference_status CHECK (status BETWEEN 0 AND 3),
    CONSTRAINT CK_ReconciliationDifference_review CHECK (reviewed_at IS NULL OR reviewed_at >= created_at)
);

-- ---------- 5. SettlementInvoice ----------
CREATE TABLE dbo.SettlementInvoice (
    invoice_id          BIGINT IDENTITY(1,1) NOT NULL,
    settlement_id       BIGINT       NOT NULL,
    invoice_no          VARCHAR(50)  NULL,
    invoice_title       NVARCHAR(100) NOT NULL,
    tax_number          VARCHAR(30)  NOT NULL,
    amount              DECIMAL(18,2) NOT NULL,
    status              SMALLINT     NOT NULL,
    original_invoice_id BIGINT       NULL,
    red_reason          NVARCHAR(500) NULL,
    created_by          BIGINT       NOT NULL,
    created_at          DATETIME2(3) NOT NULL CONSTRAINT DF_SettlementInvoice_created DEFAULT SYSDATETIME(),
    issued_at           DATETIME2(3) NULL,
    approved_by         BIGINT       NULL,
    approved_at         DATETIME2(3) NULL,
    CONSTRAINT PK_SettlementInvoice PRIMARY KEY (invoice_id),
    CONSTRAINT CK_SettlementInvoice_amount CHECK (amount <> 0),
    CONSTRAINT CK_SettlementInvoice_status CHECK (status IN (-1,0,1,2,3)),
    CONSTRAINT CK_SettlementInvoice_approve CHECK (approved_at IS NULL OR approved_at >= created_at)
);

-- ---------- 6. SettlementCarryoverAdjustment ----------
CREATE TABLE dbo.SettlementCarryoverAdjustment (
    carryover_adjustment_id BIGINT IDENTITY(1,1) NOT NULL,
    original_settlement_id  BIGINT       NOT NULL,
    refund_id               BIGINT       NOT NULL,
    target_period_month     CHAR(6)      NOT NULL,
    adjustment_amount       DECIMAL(18,2) NOT NULL,
    status                  VARCHAR(20)  NOT NULL,
    created_at              DATETIME2(3) NOT NULL CONSTRAINT DF_SettlementCarryoverAdjustment_created DEFAULT SYSDATETIME(),
    approved_by             BIGINT       NULL,
    approved_at             DATETIME2(3) NULL,
    target_settlement_id    BIGINT       NULL,
    created_by              BIGINT       NOT NULL,
    assessment_evidence     NVARCHAR(500) NOT NULL,
    CONSTRAINT PK_SettlementCarryoverAdjustment PRIMARY KEY (carryover_adjustment_id),
    CONSTRAINT CK_SettlementCarryoverAdjustment_amt CHECK (adjustment_amount < 0),
    CONSTRAINT CK_SettlementCarryoverAdjustment_status CHECK (status IN ('PENDING','APPROVED','REJECTED','APPLIED'))
);

-- ---------- 7. SettlementReviewCase ----------
CREATE TABLE dbo.SettlementReviewCase (
    review_case_id              BIGINT IDENTITY(1,1) NOT NULL,
    order_id                    BIGINT      NOT NULL,
    period_month                CHAR(6)     NOT NULL,
    reason_code                 VARCHAR(25) NOT NULL,
    refund_id                   BIGINT      NULL,
    assigned_account_id         BIGINT      NOT NULL,
    status                      VARCHAR(20) NOT NULL,
    resolution                  NVARCHAR(500) NULL,
    created_at                  DATETIME2(3) NOT NULL CONSTRAINT DF_SettlementReviewCase_created DEFAULT SYSDATETIME(),
    resolved_at                 DATETIME2(3) NULL,
    enterprise_refund_reference VARCHAR(64)  NULL,
    CONSTRAINT PK_SettlementReviewCase PRIMARY KEY (review_case_id),
    CONSTRAINT CK_SettlementReviewCase_reason CHECK (reason_code IN ('LATE_PAID','PRE_SETTLE_REFUND','PAYMENT_FAILED','POST_LOCK_REFUND','ENTERPRISE_REFUND')),
    CONSTRAINT CK_SettlementReviewCase_status CHECK (status IN ('PENDING','RESOLVED'))
);
GO
