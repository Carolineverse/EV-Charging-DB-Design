-- =====================================================
-- A2 用户与会员运营：19 张业务表
-- 依据：全组数据库物理结构设计（采样规则同步版）
-- 执行顺序：全部模块建表完成后，再执行外键和索引脚本。
-- 执行前：在 SSMS 中选择目标数据库并确认 SELECT DB_NAME()。
-- =====================================================

CREATE TABLE dbo.MemberLevel
(
    member_level_id VARCHAR(20) NOT NULL,
    level_name NVARCHAR(30) NOT NULL,
    level_description NVARCHAR(200) NULL,
    level_sort INT NOT NULL,
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_MemberLevel_status DEFAULT ('ACTIVE'),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_MemberLevel_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_MemberLevel_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_MemberLevel PRIMARY KEY CLUSTERED (member_level_id),
    CONSTRAINT UQ_MemberLevel_01 UNIQUE NONCLUSTERED (level_name),
    CONSTRAINT UQ_MemberLevel_02 UNIQUE NONCLUSTERED (level_sort),
    CONSTRAINT CK_MemberLevel_level_sort CHECK (level_sort > 0),
    CONSTRAINT CK_MemberLevel_status CHECK (status IN ('ACTIVE', 'INACTIVE'))
);
GO

CREATE TABLE dbo.UserMemberLevel
(
    user_id VARCHAR(20) NOT NULL,
    member_level_id VARCHAR(20) NOT NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserMemberLevel_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserMemberLevel_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_UserMemberLevel PRIMARY KEY CLUSTERED (user_id)
);
GO

CREATE TABLE dbo.Vehicle
(
    vehicle_id VARCHAR(20) NOT NULL,
    user_id VARCHAR(20) NULL,
    enterprise_id VARCHAR(20) NULL,
    plate_ciphertext VARBINARY(256) NOT NULL,
    plate_hash CHAR(64) NOT NULL,
    vehicle_model NVARCHAR(100) NOT NULL,
    battery_capacity_kwh DECIMAL(8,2) NOT NULL,
    max_charging_power_kw DECIMAL(8,2) NOT NULL,
    supports_fast_charge BIT NOT NULL
        CONSTRAINT DF_Vehicle_supports_fast_charge DEFAULT (0),
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_Vehicle_status DEFAULT ('ACTIVE'),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_Vehicle_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_Vehicle_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_Vehicle PRIMARY KEY CLUSTERED (vehicle_id),
    CONSTRAINT UQ_Vehicle_01 UNIQUE NONCLUSTERED (plate_hash),
    CONSTRAINT CK_Vehicle_owner CHECK (
        (user_id IS NOT NULL AND enterprise_id IS NULL)
        OR (user_id IS NULL AND enterprise_id IS NOT NULL)
    ),
    CONSTRAINT CK_Vehicle_battery_capacity CHECK (battery_capacity_kwh >= 0),
    CONSTRAINT CK_Vehicle_max_charging_power CHECK (max_charging_power_kw > 0),
    CONSTRAINT CK_Vehicle_status CHECK (status IN ('ACTIVE', 'INACTIVE'))
);
GO

CREATE TABLE dbo.FleetMember
(
    fleet_member_id VARCHAR(20) NOT NULL,
    enterprise_id VARCHAR(20) NOT NULL,
    user_id VARCHAR(20) NOT NULL,
    member_no VARCHAR(30) NULL,
    joined_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_FleetMember_joined_at DEFAULT (SYSDATETIME()),
    left_at DATETIME2(3) NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_FleetMember_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_FleetMember_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_FleetMember PRIMARY KEY CLUSTERED (fleet_member_id),
    CONSTRAINT CK_FleetMember_leave_time CHECK (left_at IS NULL OR left_at >= joined_at)
);
GO

CREATE TABLE dbo.EnterpriseCard
(
    enterprise_card_id VARCHAR(20) NOT NULL,
    enterprise_id VARCHAR(20) NOT NULL,
    card_no VARCHAR(40) NOT NULL,
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_EnterpriseCard_status DEFAULT ('ACTIVE'),
    issued_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseCard_issued_at DEFAULT (SYSDATETIME()),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseCard_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseCard_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_EnterpriseCard PRIMARY KEY CLUSTERED (enterprise_card_id),
    CONSTRAINT UQ_EnterpriseCard_01 UNIQUE NONCLUSTERED (card_no),
    CONSTRAINT CK_EnterpriseCard_status CHECK (status IN ('ACTIVE', 'CANCELLED'))
);
GO

CREATE TABLE dbo.EnterpriseCardBinding
(
    binding_id BIGINT IDENTITY(1,1) NOT NULL,
    enterprise_card_id VARCHAR(20) NOT NULL,
    vehicle_id VARCHAR(20) NOT NULL,
    fleet_member_id VARCHAR(20) NOT NULL,
    effective_start_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseCardBinding_effective_start_at DEFAULT (SYSDATETIME()),
    effective_end_at DATETIME2(3) NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseCardBinding_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseCardBinding_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_EnterpriseCardBinding PRIMARY KEY CLUSTERED (binding_id),
    CONSTRAINT CK_EnterpriseCardBinding_effective_time CHECK (
        effective_end_at IS NULL OR effective_end_at > effective_start_at
    )
);
GO

CREATE TABLE dbo.EnterpriseQuota
(
    enterprise_quota_id VARCHAR(20) NOT NULL,
    fleet_member_id VARCHAR(20) NOT NULL,
    quota_month DATE NOT NULL,
    quota_amount DECIMAL(12,2) NOT NULL,
    reserved_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_EnterpriseQuota_reserved_amount DEFAULT (0.00),
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_EnterpriseQuota_status DEFAULT ('ACTIVE'),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseQuota_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseQuota_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_EnterpriseQuota PRIMARY KEY CLUSTERED (enterprise_quota_id),
    CONSTRAINT UQ_EnterpriseQuota_01 UNIQUE NONCLUSTERED (fleet_member_id, quota_month),
    CONSTRAINT CK_EnterpriseQuota_quota_month CHECK (DAY(quota_month) = 1),
    CONSTRAINT CK_EnterpriseQuota_amounts CHECK (
        quota_amount >= 0 AND reserved_amount >= 0 AND reserved_amount <= quota_amount
    )
);
GO

CREATE TABLE dbo.Promotion
(
    promotion_id VARCHAR(20) NOT NULL,
    promotion_name NVARCHAR(100) NOT NULL,
    promotion_type VARCHAR(30) NOT NULL,
    face_value DECIMAL(10,2) NOT NULL,
    min_spend DECIMAL(10,2) NOT NULL,
    issue_start_at DATETIME2(3) NOT NULL,
    issue_end_at DATETIME2(3) NOT NULL,
    valid_start_at DATETIME2(3) NOT NULL,
    valid_end_at DATETIME2(3) NOT NULL,
    issue_quantity INT NOT NULL,
    member_level_scope VARCHAR(20) NOT NULL
        CONSTRAINT DF_Promotion_member_level_scope DEFAULT ('ALL'),
    target_audience VARCHAR(30) NOT NULL,
    redemption_rule NVARCHAR(500) NOT NULL,
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_Promotion_status DEFAULT ('DRAFT'),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_Promotion_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_Promotion_updated_at DEFAULT (SYSDATETIME()),
    reviewed_by BIGINT NULL,
    reviewed_at DATETIME2(3) NULL,
    review_result VARCHAR(20) NULL,
    CONSTRAINT PK_Promotion PRIMARY KEY CLUSTERED (promotion_id),
    CONSTRAINT CK_Promotion_amounts CHECK (face_value >= 0 AND min_spend >= 0),
    CONSTRAINT CK_Promotion_issue_quantity CHECK (issue_quantity > 0),
    CONSTRAINT CK_Promotion_issue_time CHECK (issue_end_at >= issue_start_at),
    CONSTRAINT CK_Promotion_valid_time CHECK (valid_end_at >= valid_start_at),
    CONSTRAINT CK_Promotion_member_level_scope CHECK (member_level_scope IN ('ALL', 'SPECIFIED')),
    CONSTRAINT CK_Promotion_status CHECK (status IN ('DRAFT', 'ACTIVE', 'PAUSED', 'ENDED')),
    CONSTRAINT CK_Promotion_review CHECK (
        (reviewed_by IS NULL AND reviewed_at IS NULL AND review_result IS NULL)
        OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL
            AND review_result IN ('APPROVED', 'REJECTED'))
    ),
    CONSTRAINT CK_Promotion_active_review CHECK (
        status <> 'ACTIVE'
        OR (review_result IS NOT NULL AND review_result = 'APPROVED')
    )
);
GO

CREATE TABLE dbo.PromotionStation
(
    promotion_station_id BIGINT IDENTITY(1,1) NOT NULL,
    promotion_id VARCHAR(20) NOT NULL,
    station_id VARCHAR(20) NOT NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PromotionStation_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_PromotionStation PRIMARY KEY CLUSTERED (promotion_station_id),
    CONSTRAINT UQ_PromotionStation_01 UNIQUE NONCLUSTERED (promotion_id, station_id)
);
GO

CREATE TABLE dbo.PromotionMemberLevel
(
    promotion_member_level_id BIGINT IDENTITY(1,1) NOT NULL,
    promotion_id VARCHAR(20) NOT NULL,
    member_level_id VARCHAR(20) NOT NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PromotionMemberLevel_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_PromotionMemberLevel PRIMARY KEY CLUSTERED (promotion_member_level_id),
    CONSTRAINT UQ_PromotionMemberLevel_01 UNIQUE NONCLUSTERED (promotion_id, member_level_id)
);
GO

CREATE TABLE dbo.UserCoupon
(
    user_coupon_id VARCHAR(20) NOT NULL,
    promotion_id VARCHAR(20) NOT NULL,
    user_id VARCHAR(20) NOT NULL,
    coupon_code VARCHAR(40) NOT NULL,
    face_value DECIMAL(10,2) NOT NULL,
    min_spend DECIMAL(10,2) NOT NULL,
    issued_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserCoupon_issued_at DEFAULT (SYSDATETIME()),
    valid_start_at DATETIME2(3) NOT NULL,
    valid_end_at DATETIME2(3) NOT NULL,
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_UserCoupon_status DEFAULT ('UNUSED'),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserCoupon_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserCoupon_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_UserCoupon PRIMARY KEY CLUSTERED (user_coupon_id),
    CONSTRAINT UQ_UserCoupon_01 UNIQUE NONCLUSTERED (coupon_code),
    CONSTRAINT CK_UserCoupon_amounts CHECK (face_value >= 0 AND min_spend >= 0),
    CONSTRAINT CK_UserCoupon_valid_time CHECK (valid_end_at >= valid_start_at),
    CONSTRAINT CK_UserCoupon_status CHECK (status IN ('UNUSED', 'USED', 'REVOKED'))
);
GO

CREATE TABLE dbo.CouponRedemption
(
    coupon_redemption_id BIGINT IDENTITY(1,1) NOT NULL,
    user_coupon_id VARCHAR(20) NOT NULL,
    order_id BIGINT NOT NULL,
    redeemed_amount DECIMAL(10,2) NOT NULL,
    redeemed_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_CouponRedemption_redeemed_at DEFAULT (SYSDATETIME()),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_CouponRedemption_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_CouponRedemption PRIMARY KEY CLUSTERED (coupon_redemption_id),
    CONSTRAINT UQ_CouponRedemption_01 UNIQUE NONCLUSTERED (user_coupon_id),
    CONSTRAINT UQ_CouponRedemption_02 UNIQUE NONCLUSTERED (order_id),
    CONSTRAINT CK_CouponRedemption_redeemed_amount CHECK (redeemed_amount >= 0)
);
GO

CREATE TABLE dbo.UserWallet
(
    user_id VARCHAR(20) NOT NULL,
    balance DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_UserWallet_balance DEFAULT (0.00),
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_UserWallet_status DEFAULT ('ACTIVE'),
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserWallet_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserWallet_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_UserWallet PRIMARY KEY CLUSTERED (user_id),
    CONSTRAINT CK_UserWallet_balance CHECK (balance >= 0),
    CONSTRAINT CK_UserWallet_status CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED'))
);
GO

CREATE TABLE dbo.WalletTransaction
(
    wallet_transaction_id BIGINT IDENTITY(1,1) NOT NULL,
    transaction_no VARCHAR(40) NOT NULL,
    user_id VARCHAR(20) NOT NULL,
    transaction_type VARCHAR(30) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    balance_before DECIMAL(12,2) NOT NULL,
    order_id BIGINT NULL,
    external_transaction_no VARCHAR(100) NULL,
    remark NVARCHAR(200) NULL,
    transaction_at DATETIME2(3) NOT NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_WalletTransaction_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_WalletTransaction PRIMARY KEY CLUSTERED (wallet_transaction_id),
    CONSTRAINT UQ_WalletTransaction_01 UNIQUE NONCLUSTERED (transaction_no),
    CONSTRAINT CK_WalletTransaction_amount CHECK (amount > 0),
    CONSTRAINT CK_WalletTransaction_balance_before CHECK (balance_before >= 0),
    CONSTRAINT CK_WalletTransaction_type CHECK (
        transaction_type IN ('RECHARGE', 'REFUND', 'MANUAL_CREDIT', 'CHARGE_PAYMENT', 'MANUAL_DEBIT')
    ),
    CONSTRAINT CK_WalletTransaction_external_no CHECK (
        transaction_type NOT IN ('REFUND', 'CHARGE_PAYMENT')
        OR (external_transaction_no IS NOT NULL AND LEN(LTRIM(RTRIM(external_transaction_no))) > 0)
    )
);
GO

CREATE TABLE dbo.PersonalInvoiceApplication
(
    invoice_application_id VARCHAR(20) NOT NULL,
    user_id VARCHAR(20) NOT NULL,
    order_id BIGINT NOT NULL,
    invoice_title NVARCHAR(100) NOT NULL,
    recipient_email VARCHAR(254) NOT NULL,
    invoice_amount DECIMAL(12,2) NOT NULL,
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_PersonalInvoiceApplication_status DEFAULT ('PENDING'),
    applied_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PersonalInvoiceApplication_applied_at DEFAULT (SYSDATETIME()),
    issued_at DATETIME2(3) NULL,
    invoice_number VARCHAR(50) NULL,
    invoice_code VARCHAR(50) NULL,
    invoice_file_url NVARCHAR(500) NULL,
    reject_reason NVARCHAR(300) NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PersonalInvoiceApplication_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PersonalInvoiceApplication_updated_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_PersonalInvoiceApplication PRIMARY KEY CLUSTERED (invoice_application_id),
    CONSTRAINT UQ_PersonalInvoiceApplication_01 UNIQUE NONCLUSTERED (order_id),
    CONSTRAINT CK_PersonalInvoiceApplication_amount CHECK (invoice_amount >= 0),
    CONSTRAINT CK_PersonalInvoiceApplication_status CHECK (
        status IN ('PENDING', 'PROCESSING', 'ISSUED', 'REJECTED', 'CANCELLED')
    ),
    CONSTRAINT CK_PersonalInvoiceApplication_issued CHECK (
        status <> 'ISSUED'
        OR (issued_at IS NOT NULL AND invoice_number IS NOT NULL
            AND LEN(LTRIM(RTRIM(invoice_number))) > 0)
    ),
    CONSTRAINT CK_PersonalInvoiceApplication_rejected CHECK (
        status <> 'REJECTED'
        OR (reject_reason IS NOT NULL AND LEN(LTRIM(RTRIM(reject_reason))) > 0)
    )
);
GO

CREATE TABLE dbo.EnterpriseSettlement
(
    enterprise_settlement_id VARCHAR(20) NOT NULL,
    enterprise_id VARCHAR(20) NOT NULL,
    billing_period_start DATE NOT NULL,
    total_order_count INT NOT NULL
        CONSTRAINT DF_EnterpriseSettlement_total_order_count DEFAULT (0),
    total_energy_kwh DECIMAL(12,3) NOT NULL
        CONSTRAINT DF_EnterpriseSettlement_total_energy_kwh DEFAULT (0),
    total_amount DECIMAL(12,2) NOT NULL
        CONSTRAINT DF_EnterpriseSettlement_total_amount DEFAULT (0.00),
    generated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseSettlement_generated_at DEFAULT (SYSDATETIME()),
    confirmed_at DATETIME2(3) NULL,
    paid_at DATETIME2(3) NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseSettlement_created_at DEFAULT (SYSDATETIME()),
    updated_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseSettlement_updated_at DEFAULT (SYSDATETIME()),
    payment_reference VARCHAR(100) NULL,
    CONSTRAINT PK_EnterpriseSettlement PRIMARY KEY CLUSTERED (enterprise_settlement_id),
    CONSTRAINT UQ_EnterpriseSettlement_01 UNIQUE NONCLUSTERED (enterprise_id, billing_period_start),
    CONSTRAINT CK_EnterpriseSettlement_period CHECK (DAY(billing_period_start) = 1),
    CONSTRAINT CK_EnterpriseSettlement_totals CHECK (
        total_order_count >= 0 AND total_energy_kwh >= 0 AND total_amount >= 0
    ),
    CONSTRAINT CK_EnterpriseSettlement_payment CHECK (
        (paid_at IS NULL AND payment_reference IS NULL)
        OR (paid_at IS NOT NULL AND confirmed_at IS NOT NULL
            AND paid_at >= confirmed_at
            AND payment_reference IS NOT NULL
            AND LEN(LTRIM(RTRIM(payment_reference))) > 0)
    ),
    CONSTRAINT CK_EnterpriseSettlement_confirmed_at CHECK (
        confirmed_at IS NULL OR confirmed_at >= generated_at
    )
);
GO

CREATE TABLE dbo.EnterpriseSettlementDetail
(
    enterprise_settlement_detail_id BIGINT IDENTITY(1,1) NOT NULL,
    enterprise_settlement_id VARCHAR(20) NOT NULL,
    order_id BIGINT NOT NULL,
    fleet_member_id VARCHAR(20) NOT NULL,
    vehicle_id VARCHAR(20) NOT NULL,
    payable_amount DECIMAL(12,2) NOT NULL,
    energy_kwh DECIMAL(12,3) NOT NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseSettlementDetail_created_at DEFAULT (SYSDATETIME()),
    CONSTRAINT PK_EnterpriseSettlementDetail PRIMARY KEY CLUSTERED (enterprise_settlement_detail_id),
    CONSTRAINT UQ_EnterpriseSettlementDetail_01 UNIQUE NONCLUSTERED (order_id),
    CONSTRAINT CK_EnterpriseSettlementDetail_amounts CHECK (payable_amount >= 0 AND energy_kwh >= 0)
);
GO

CREATE TABLE dbo.EnterpriseServiceApplication
(
    application_id BIGINT IDENTITY(1,1) NOT NULL,
    enterprise_id VARCHAR(20) NOT NULL,
    application_type VARCHAR(20) NOT NULL,
    station_id VARCHAR(20) NULL,
    request_details NVARCHAR(1000) NOT NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_EnterpriseServiceApplication_created_at DEFAULT (SYSDATETIME()),
    status VARCHAR(20) NOT NULL
        CONSTRAINT DF_EnterpriseServiceApplication_status DEFAULT ('PENDING'),
    reviewed_by BIGINT NULL,
    reviewed_at DATETIME2(3) NULL,
    decision NVARCHAR(500) NULL,
    CONSTRAINT PK_EnterpriseServiceApplication PRIMARY KEY CLUSTERED (application_id),
    CONSTRAINT CK_EnterpriseServiceApplication_type CHECK (
        application_type IN ('CORPORATE', 'ENTERPRISE_PRICE')
    ),
    CONSTRAINT CK_EnterpriseServiceApplication_station CHECK (
        application_type <> 'ENTERPRISE_PRICE' OR station_id IS NOT NULL
    ),
    CONSTRAINT CK_EnterpriseServiceApplication_status CHECK (
        status IN ('PENDING', 'APPROVED', 'REJECTED')
    ),
    CONSTRAINT CK_EnterpriseServiceApplication_review CHECK (
        (status = 'PENDING' AND reviewed_by IS NULL AND reviewed_at IS NULL AND decision IS NULL)
        OR (status IN ('APPROVED', 'REJECTED') AND reviewed_by IS NOT NULL
            AND reviewed_at IS NOT NULL AND decision IS NOT NULL
            AND LEN(LTRIM(RTRIM(decision))) > 0)
    )
);
GO

CREATE TABLE dbo.PersonalInvoiceAdjustment
(
    adjustment_id BIGINT IDENTITY(1,1) NOT NULL,
    invoice_application_id VARCHAR(20) NOT NULL,
    refund_id BIGINT NOT NULL,
    adjustment_amount DECIMAL(12,2) NOT NULL,
    status VARCHAR(20) NOT NULL,
    red_invoice_no VARCHAR(50) NULL,
    created_at DATETIME2(3) NOT NULL
        CONSTRAINT DF_PersonalInvoiceAdjustment_created_at DEFAULT (SYSDATETIME()),
    issued_at DATETIME2(3) NULL,
    handled_by BIGINT NULL,
    reason NVARCHAR(500) NOT NULL,
    CONSTRAINT PK_PersonalInvoiceAdjustment PRIMARY KEY CLUSTERED (adjustment_id),
    CONSTRAINT UQ_PersonalInvoiceAdjustment_01 UNIQUE NONCLUSTERED (refund_id),
    CONSTRAINT CK_PersonalInvoiceAdjustment_amount CHECK (adjustment_amount >= 0),
    CONSTRAINT CK_PersonalInvoiceAdjustment_status CHECK (
        status IN ('PENDING', 'ISSUED', 'FAILED', 'NO_ADJUSTMENT')
    ),
    CONSTRAINT CK_PersonalInvoiceAdjustment_issued CHECK (
        (status = 'ISSUED' AND issued_at IS NOT NULL
            AND red_invoice_no IS NOT NULL AND LEN(LTRIM(RTRIM(red_invoice_no))) > 0)
        OR (status <> 'ISSUED' AND issued_at IS NULL)
    ),
    CONSTRAINT CK_PersonalInvoiceAdjustment_no_adjustment CHECK (
        status <> 'NO_ADJUSTMENT' OR adjustment_amount = 0
    )
);
GO
