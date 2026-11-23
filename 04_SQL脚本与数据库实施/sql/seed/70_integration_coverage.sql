-- Supplemental integration data. Run after C reports and D post-lock refunds.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'EV_B_TEST' THROW 52600, N'仅在联调 EV_B_TEST 中加载补充种子', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @admin BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username='demo_admin_r01');
    IF @admin IS NULL THROW 52601, N'缺少 R 基础种子', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DeviceCommunicationConfig WHERE config_id=1)
        INSERT INTO dbo.DeviceCommunicationConfig (config_id) VALUES (1);
    INSERT INTO dbo.MemberLevel (member_level_id, level_name, level_sort)
    SELECT s.id, s.name, s.sort
    FROM (VALUES ('L01',N'普通',1),('L02',N'银卡',2),('L03',N'金卡',3)) s(id,name,sort)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.MemberLevel l WHERE l.member_level_id=s.id);
    IF NOT EXISTS (SELECT 1 FROM dbo.UserMemberLevel WHERE user_id='B_DEMO_USER01')
        INSERT INTO dbo.UserMemberLevel (user_id, member_level_id) VALUES ('B_DEMO_USER01','L01');

    DECLARE @i INT = 1;
    DECLARE @effective DATETIME2(3) = '2026-06-01T00:00:00';
    DECLARE @created DATETIME2(3) = '2026-10-05T09:59:59.123';
    DECLARE @start DATETIME2(3) = '2026-10-05T10:00:00';
    DECLARE @ended DATETIME2(3) = '2026-10-05T11:00:00';
    DECLARE @priced DATETIME2(3) = '2026-10-05T11:00:04';
    DECLARE @settled DATETIME2(3) = '2026-10-05T11:00:05';
    WHILE @i <= 20
    BEGIN
        DECLARE @suffix CHAR(2) = RIGHT('00'+CONVERT(VARCHAR(2),@i),2);
        DECLARE @staff VARCHAR(20) = 'BLK_STAFF_'+@suffix, @user VARCHAR(20) = 'BLK_USER_'+@suffix,
                @enterprise VARCHAR(20) = 'BLK_ENT_'+@suffix, @operator VARCHAR(20) = 'BLK_OP_'+@suffix,
                @station VARCHAR(20) = 'BLK_ST_'+@suffix, @pile VARCHAR(20) = 'BLK_PILE_'+@suffix,
                @gun VARCHAR(20) = 'BLK_GUN_'+@suffix, @vehicle VARCHAR(20) = 'BLK_VEH_'+@suffix,
                @member VARCHAR(20) = 'BLK_MEM_'+@suffix, @card VARCHAR(20) = 'BLK_CARD_'+@suffix,
                @quota VARCHAR(20) = 'BLK_QUOTA_'+@suffix, @bill VARCHAR(20) = 'BLK_BILL_'+@suffix,
                @level VARCHAR(20) = 'L0'+CONVERT(VARCHAR(1),1+(@i-1)%3),
                @fault VARCHAR(20) = 'BLK_FAULT_'+@suffix, @wallet_txn VARCHAR(40) = 'BLK_WALLET_'+@suffix,
                @start_report VARCHAR(50) = 'BLK_START_'+@suffix, @end_report VARCHAR(50) = 'BLK_END_'+@suffix,
                @device_session VARCHAR(64) = 'BLK_SESS_'+@suffix, @event VARCHAR(64) = 'BLK_EVT_'+@suffix;
        DECLARE @snapshot NVARCHAR(MAX) = CONCAT(N'{"status":"CONFIRMED","report_id":"',@start_report,
                                                 N'","device_session_no":"',@device_session,N'"}');
        DECLARE @version BIGINT = 921260000 + @i;

        INSERT INTO dbo.SysAccount (username,password_hash,role_id)
        SELECT a.username,'REPLACE_WITH_REAL_PASSWORD_HASH',r.role_id
        FROM (VALUES (@staff,'R02'),(@user,'R04'),(@enterprise,'R05')) a(username,role_code)
        JOIN dbo.SysRole r ON r.role_code=a.role_code
        WHERE NOT EXISTS (SELECT 1 FROM dbo.SysAccount x WHERE x.username=a.username);
        DECLARE @staff_account BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username=@staff),
                @user_account BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username=@user),
                @enterprise_account BIGINT = (SELECT account_id FROM dbo.SysAccount WHERE username=@enterprise);
        IF NOT EXISTS (SELECT 1 FROM dbo.StaffProfile WHERE staff_id=@staff)
            INSERT INTO dbo.StaffProfile (staff_id,account_id,employee_no,staff_name,gender,birth_date,employment_status)
            VALUES (@staff,@staff_account,@staff,N'合成运维人员','UNKNOWN','19900101','ACTIVE');
        IF NOT EXISTS (SELECT 1 FROM dbo.UserProfile WHERE user_id=@user)
        BEGIN
            DECLARE @phone NVARCHAR(11) = CONCAT(N'13800002', RIGHT('000'+@suffix,3));
            DECLARE @phone_cipher VARBINARY(256);
            EXEC dbo.usp_EncryptSensitive @phone, @phone_cipher OUTPUT;
            INSERT INTO dbo.UserProfile (user_id,account_id,phone_ciphertext,phone_hash,real_name_status,registered_at,status)
            VALUES (@user,@user_account,@phone_cipher,CONVERT(CHAR(64),HASHBYTES('SHA2_256',@phone),2),'UNVERIFIED',@effective,'ACTIVE');
        END;
        IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseProfile WHERE enterprise_id=@enterprise)
        BEGIN
            DECLARE @contact_phone NVARCHAR(11) = CONCAT(N'13900002', RIGHT('000'+@suffix,3));
            DECLARE @contact_cipher VARBINARY(256);
            EXEC dbo.usp_EncryptSensitive @contact_phone, @contact_cipher OUTPUT;
            INSERT INTO dbo.EnterpriseProfile (enterprise_id,account_id,enterprise_name,credit_code,contact_name,contact_phone_ciphertext,status)
            VALUES (@enterprise,@enterprise_account,N'合成企业 '+@suffix,@enterprise,N'演示联系人',@contact_cipher,'ACTIVE');
        END;
        IF NOT EXISTS (SELECT 1 FROM dbo.Operator WHERE operator_id=@operator)
            INSERT INTO dbo.Operator (operator_id,operator_name)
            VALUES (@operator,N'合成运营商 '+@suffix);
        IF NOT EXISTS (SELECT 1 FROM dbo.ChargingStation WHERE station_id=@station)
            INSERT INTO dbo.ChargingStation (station_id,station_name,address,longitude,latitude,operator_id,total_spaces,business_hours,parking_fee_standard,workorder_notice_account_id)
            VALUES (@station,N'合成场站 '+@suffix,N'虚构地址',116.4,39.9,@operator,2,N'全天',N'免费',@admin);
        IF NOT EXISTS (SELECT 1 FROM dbo.ChargingPile WHERE pile_id=@pile)
            INSERT INTO dbo.ChargingPile (pile_id,station_id,device_model,rated_power_kw,communication_protocol,commissioned_date,warranty_end_date,status)
            VALUES (@pile,@station,N'BLK-DC120',120,N'OCPP-1.6',@effective,'20280101','IDLE');
        IF NOT EXISTS (SELECT 1 FROM dbo.ChargingGun WHERE gun_id=@gun)
            INSERT INTO dbo.ChargingGun (gun_id,pile_id,gun_sequence,gun_type,interface_standard,max_output_power_kw,status)
            VALUES (@gun,@pile,1,'DC_FAST',N'GB/T',120,'IDLE');
        IF NOT EXISTS (SELECT 1 FROM dbo.DeviceStatusHistory WHERE pile_id=@pile AND changed_at=@effective AND change_source='SYSTEM_RULE')
            INSERT INTO dbo.DeviceStatusHistory (pile_id,old_status,new_status,changed_at,change_reason,change_source)
            VALUES (@pile,'UNKNOWN','IDLE',@effective,N'设备验收上线','SYSTEM_RULE');
        IF NOT EXISTS (SELECT 1 FROM dbo.DeviceAssetCase WHERE pile_id=@pile AND case_type='ACCEPTANCE' AND submitted_at=@effective)
            INSERT INTO dbo.DeviceAssetCase (pile_id,case_type,submitted_by,submitted_at,details,status,reviewed_by,reviewed_at,decision)
            VALUES (@pile,'ACCEPTANCE',@staff_account,@effective,N'设备验收','COMPLETED',@admin,@start,N'验收完成');
        IF NOT EXISTS (SELECT 1 FROM dbo.DeviceFaultCodeMapping WHERE device_model=N'BLK-DC120' AND raw_fault_code=@fault)
            INSERT INTO dbo.DeviceFaultCodeMapping (device_model,raw_fault_code,alarm_code)
            VALUES (N'BLK-DC120',@fault,'AL001');
        IF NOT EXISTS (SELECT 1 FROM dbo.UserMemberLevel WHERE user_id=@user)
            INSERT INTO dbo.UserMemberLevel (user_id,member_level_id)
            VALUES (@user,@level);
        IF NOT EXISTS (SELECT 1 FROM dbo.Vehicle WHERE vehicle_id=@vehicle)
        BEGIN
            DECLARE @plate NVARCHAR(8) = CONCAT(N'京B100', @suffix);
            DECLARE @plate_cipher VARBINARY(256);
            EXEC dbo.usp_EncryptSensitive @plate, @plate_cipher OUTPUT;
            INSERT INTO dbo.Vehicle (vehicle_id,enterprise_id,plate_ciphertext,plate_hash,vehicle_model,battery_capacity_kwh,max_charging_power_kw,supports_fast_charge)
            VALUES (@vehicle,@enterprise,@plate_cipher,CONVERT(CHAR(64),HASHBYTES('SHA2_256',@plate),2),N'合成车型',70,100,1);
        END;
        IF NOT EXISTS (SELECT 1 FROM dbo.FleetMember WHERE fleet_member_id=@member)
            INSERT INTO dbo.FleetMember (fleet_member_id,enterprise_id,user_id,member_no,joined_at)
            VALUES (@member,@enterprise,@user,@member,@effective);
        IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseCard WHERE enterprise_card_id=@card)
            INSERT INTO dbo.EnterpriseCard (enterprise_card_id,enterprise_id,card_no,issued_at)
            VALUES (@card,@enterprise,@card,@effective);
        IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseCardBinding WHERE enterprise_card_id=@card AND effective_start_at=@effective)
            INSERT INTO dbo.EnterpriseCardBinding (enterprise_card_id,vehicle_id,fleet_member_id,effective_start_at)
            VALUES (@card,@vehicle,@member,@effective);
        IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseQuota WHERE enterprise_quota_id=@quota)
            INSERT INTO dbo.EnterpriseQuota (enterprise_quota_id,fleet_member_id,quota_month,quota_amount,reserved_amount)
            VALUES (@quota,@member,'20261001',100,0);
        IF NOT EXISTS (SELECT 1 FROM dbo.BillingRuleVersion WHERE rule_version_id=@version)
            INSERT INTO dbo.BillingRuleVersion (rule_version_id,station_id,enterprise_id,free_minutes,minimum_amount,effective_from,status)
            VALUES (@version,@station,@enterprise,0,5,@effective,'ACTIVE');
        IF NOT EXISTS (SELECT 1 FROM dbo.BillingRule WHERE rule_version_id=@version AND period_start_time='00:00:00')
            INSERT INTO dbo.BillingRule (rule_version_id,period_type,period_start_time,period_end_time,electricity_price,service_price)
            VALUES (@version,N'平','00:00:00','23:59:00',2,1);
        DECLARE @binding BIGINT = (SELECT binding_id FROM dbo.EnterpriseCardBinding WHERE enterprise_card_id=@card AND effective_start_at=@effective);
        DECLARE @rule BIGINT = (SELECT billing_rule_id FROM dbo.BillingRule WHERE rule_version_id=@version AND period_start_time='00:00:00');
        IF NOT EXISTS (SELECT 1 FROM dbo.ChargingOrder WHERE user_id=@user AND gun_id=@gun AND created_at=@created)
            INSERT INTO dbo.ChargingOrder (order_type,user_id,gun_id,binding_id,enterprise_quota_id,start_time,end_time,energy_kwh,status,gross_amount,minimum_adjustment,discount_amount,paid_amount,refund_amount,created_at,updated_at,opening_station_id,settled_at,startup_rule_version_id,priced_at,device_released_at)
            VALUES ('ENTERPRISE',@user,@gun,@binding,@quota,@start,@ended,1,'PAID',5,2,0,5,0,@created,@ended,@station,@settled,@version,@priced,@ended);
        DECLARE @order BIGINT = (SELECT order_id FROM dbo.ChargingOrder WHERE user_id=@user AND gun_id=@gun AND created_at=@created);
        IF NOT EXISTS (SELECT 1 FROM dbo.OrderFeeDetail WHERE order_id=@order AND segment_start=@start)
            INSERT INTO dbo.OrderFeeDetail (order_id,billing_rule_id,segment_start,segment_end,segment_energy_kwh,free_service_fee)
            VALUES (@order,@rule,@start,@ended,1,0);
        IF NOT EXISTS (SELECT 1 FROM dbo.DeviceReport WHERE report_id=@start_report)
            INSERT INTO dbo.DeviceReport (report_id,pile_id,generated_at,received_at,payload_hash,processing_status,processed_at,report_type)
            VALUES (@start_report,@pile,@start,@start,REPLICATE('0',64),'PROCESSED',@start,'CHARGING_START');
        IF NOT EXISTS (SELECT 1 FROM dbo.DeviceReport WHERE report_id=@end_report)
            INSERT INTO dbo.DeviceReport (report_id,pile_id,generated_at,received_at,payload_hash,processing_status,processed_at,report_type)
            VALUES (@end_report,@pile,@ended,@ended,REPLICATE('0',64),'PROCESSED',@ended,'CHARGING_END');
        IF NOT EXISTS (SELECT 1 FROM dbo.ChargingMeterSample WHERE order_id=@order AND sample_type='START')
            INSERT INTO dbo.ChargingMeterSample (order_id,device_session_no,report_id,collected_at,cumulative_kwh,sample_type,validation_status)
            VALUES (@order,@device_session,@start_report,@start,0,'START','VALID');
        IF NOT EXISTS (SELECT 1 FROM dbo.ChargingMeterSample WHERE order_id=@order AND sample_type='END')
            INSERT INTO dbo.ChargingMeterSample (order_id,device_session_no,report_id,collected_at,cumulative_kwh,sample_type,validation_status)
            VALUES (@order,@device_session,@end_report,@ended,1,'END','VALID');
        IF NOT EXISTS (SELECT 1 FROM dbo.OrderCommand WHERE order_id=@order AND command_type='START')
            INSERT INTO dbo.OrderCommand (order_id,command_type,status,created_at,deadline_at,confirmed_at,processed_event_id,result_hash,result_snapshot)
            VALUES (@order,'START','CONFIRMED',@created,DATEADD(SECOND,30,@created),@start,@event,LOWER(CONVERT(CHAR(64),HASHBYTES('SHA2_256',@snapshot),2)),@snapshot);
        IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseServiceApplication WHERE enterprise_id=@enterprise AND application_type='CORPORATE' AND request_details=N'开通企业月结')
            INSERT INTO dbo.EnterpriseServiceApplication (enterprise_id,application_type,request_details,status,reviewed_by,reviewed_at,decision)
            VALUES (@enterprise,'CORPORATE',N'开通企业月结','APPROVED',@admin,@effective,N'同意开通');
        IF NOT EXISTS (SELECT 1 FROM dbo.UserWallet WHERE user_id=@user)
            INSERT INTO dbo.UserWallet (user_id,balance)
            VALUES (@user,20);
        IF NOT EXISTS (SELECT 1 FROM dbo.WalletTransaction WHERE transaction_no=@wallet_txn)
            INSERT INTO dbo.WalletTransaction (transaction_no,user_id,transaction_type,amount,balance_before,transaction_at)
            VALUES (@wallet_txn,@user,'RECHARGE',20,0,@effective);

        -- Generate a real enterprise bill. Leave it unconfirmed and unpaid.
        IF NOT EXISTS (SELECT 1 FROM dbo.EnterpriseSettlement WHERE enterprise_id=@enterprise AND billing_period_start='20261001')
            EXEC dbo.usp_A2_GenerateEnterpriseSettlement @bill, @enterprise, '20261001';

        SET @i += 1;
    END;

    -- Reuse the 20 seeded D post-lock refunds. No new personal order or refund.
    DECLARE @invoices TABLE (
        refund_id BIGINT PRIMARY KEY, order_id BIGINT UNIQUE, station_id VARCHAR(20),
        user_id VARCHAR(20), paid_amount DECIMAL(12,2), refunded_at DATETIME2(3),
        refund_amount DECIMAL(12,2), priced_at DATETIME2(3), business_key VARCHAR(64) NOT NULL UNIQUE
    );
    INSERT INTO @invoices
    SELECT r.refund_id,o.order_id,s.station_id,o.user_id,p.pay_amount,r.refunded_at,r.refund_amount,o.priced_at,
           s.station_id+'_'+s.period_month
    FROM dbo.SettlementCarryoverAdjustment c
    JOIN dbo.SettlementStatement s ON s.settlement_id=c.original_settlement_id
    JOIN dbo.RefundRecord r ON r.refund_id=c.refund_id
    JOIN dbo.PaymentRecord p ON p.payment_id=r.payment_id
    JOIN dbo.ChargingOrder o ON o.order_id=p.order_id
    JOIN dbo.SettlementDetail d ON d.settlement_id=s.settlement_id AND d.order_id=o.order_id
    WHERE c.status='APPLIED' AND r.status='SUCCESS' AND r.refunded_at>s.confirmed_at
      AND r.refund_no='D-DEMO-REF-'+s.station_id+'-'+s.period_month
      AND p.pay_channel='OTHER' AND p.transaction_no='D-DEMO-PAY-'+s.station_id+'-'+s.period_month;
    IF (SELECT COUNT(*) FROM @invoices) <> 20 THROW 52602, N'缺少 20 笔联调锁定后退款', 1;

    DECLARE @promo TABLE (seq INT PRIMARY KEY, order_id BIGINT, station_id VARCHAR(20), user_id VARCHAR(20), priced_at DATETIME2(3));
    INSERT INTO @promo
    SELECT ROW_NUMBER() OVER (ORDER BY business_key),order_id,station_id,user_id,priced_at FROM @invoices;
    INSERT INTO dbo.Promotion (promotion_id,promotion_name,promotion_type,face_value,min_spend,
        issue_start_at,issue_end_at,valid_start_at,valid_end_at,issue_quantity,member_level_scope,
        target_audience,redemption_rule,status,reviewed_by,reviewed_at,review_result)
    SELECT 'BLK_PR_'+CONVERT(VARCHAR(2),p.seq),N'联调券 3 元','GENERAL',3,5,
        @effective,'20261001',@effective,'20261001',1,'SPECIFIED','MEMBER',N'指定场站满 5 元减 3 元',
        'ENDED',@admin,@effective,'APPROVED'
    FROM @promo p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Promotion x WHERE x.promotion_id='BLK_PR_'+CONVERT(VARCHAR(2),p.seq));

    INSERT INTO dbo.PromotionStation (promotion_id,station_id)
    SELECT 'BLK_PR_'+CONVERT(VARCHAR(2),p.seq),p.station_id FROM @promo p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.PromotionStation x WHERE x.promotion_id='BLK_PR_'+CONVERT(VARCHAR(2),p.seq) AND x.station_id=p.station_id);

    INSERT INTO dbo.PromotionMemberLevel (promotion_id,member_level_id)
    SELECT 'BLK_PR_'+CONVERT(VARCHAR(2),p.seq),'L01' FROM @promo p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.PromotionMemberLevel x WHERE x.promotion_id='BLK_PR_'+CONVERT(VARCHAR(2),p.seq) AND x.member_level_id='L01');

    INSERT INTO dbo.UserCoupon (user_coupon_id,promotion_id,user_id,coupon_code,face_value,min_spend,issued_at,valid_start_at,valid_end_at,status)
    SELECT 'BLK_CP_'+CONVERT(VARCHAR(2),p.seq),'BLK_PR_'+CONVERT(VARCHAR(2),p.seq),p.user_id,
           'BLK_CP_'+CONVERT(VARCHAR(2),p.seq),3,5,@effective,@effective,'20261001','USED'
    FROM @promo p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.UserCoupon x WHERE x.user_coupon_id='BLK_CP_'+CONVERT(VARCHAR(2),p.seq));

    INSERT INTO dbo.CouponRedemption (user_coupon_id,order_id,redeemed_amount,redeemed_at)
    SELECT 'BLK_CP_'+CONVERT(VARCHAR(2),p.seq),p.order_id,3,p.priced_at FROM @promo p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.CouponRedemption x WHERE x.order_id=p.order_id);

    INSERT INTO dbo.PersonalInvoiceApplication (invoice_application_id,user_id,order_id,invoice_title,recipient_email,
        invoice_amount,status,applied_at,issued_at,invoice_number)
    SELECT 'BLK_PI_'+CONVERT(VARCHAR(2),p.seq),r.user_id,r.order_id,N'联调个人发票','fixture@example.invalid',
           r.paid_amount,'ISSUED',r.priced_at,DATEADD(MILLISECOND,-1,r.refunded_at),'BLK_INV_'+r.business_key
    FROM @invoices r JOIN @promo p ON p.order_id=r.order_id
    WHERE NOT EXISTS (SELECT 1 FROM dbo.PersonalInvoiceApplication a WHERE a.order_id=r.order_id);

    INSERT INTO dbo.PersonalInvoiceAdjustment (invoice_application_id,refund_id,adjustment_amount,status,reason)
    SELECT a.invoice_application_id,r.refund_id,r.refund_amount,'PENDING',N'锁定后成功退款对应的个人发票待调整'
    FROM @invoices r JOIN dbo.PersonalInvoiceApplication a ON a.order_id=r.order_id
    WHERE NOT EXISTS (SELECT 1 FROM dbo.PersonalInvoiceAdjustment x WHERE x.refund_id=r.refund_id);

    IF EXISTS (
        SELECT 1 FROM dbo.ChargingOrder o
        LEFT JOIN dbo.v_OrderSettlementSource v ON v.order_id=o.order_id
        WHERE o.opening_station_id LIKE 'BLK[_]ST[_]%'
          AND (v.order_id IS NULL OR ISNULL(v.is_settleable,1)<>0 OR ISNULL(v.eligibility_reason,'')<>'ENTERPRISE_RECEIPT_MISMATCH'
               OR EXISTS (SELECT 1 FROM dbo.SettlementDetail d WHERE d.order_id=o.order_id))
    ) THROW 52603, N'专用企业订单来源资格或结算明细不符合预期', 1;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
