-- ---------- 1. SysRole ----------
CREATE TABLE dbo.SysRole (
    role_id      TINYINT      NOT NULL,
    role_code    VARCHAR(30)  NOT NULL,
    role_name    NVARCHAR(50) NOT NULL,
    subject_type VARCHAR(20)  NOT NULL,
    role_desc    NVARCHAR(500) NULL,
    status       TINYINT      NOT NULL CONSTRAINT DF_SysRole_status DEFAULT 1,
    created_at   DATETIME2(3) NOT NULL CONSTRAINT DF_SysRole_created DEFAULT SYSDATETIME(),
    updated_at   DATETIME2(3) NOT NULL CONSTRAINT DF_SysRole_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_SysRole PRIMARY KEY (role_id),
    CONSTRAINT UQ_SysRole_01 UNIQUE (role_code),
    CONSTRAINT CK_SysRole_RoleId CHECK (role_id BETWEEN 1 AND 5),
    CONSTRAINT CK_SysRole_subject CHECK (subject_type IN ('STAFF','PERSONAL','ENTERPRISE')),
    CONSTRAINT CK_SysRole_status CHECK (status IN (0,1))
);

-- ---------- 2. SysAccount ----------
CREATE TABLE dbo.SysAccount (
    account_id         BIGINT IDENTITY(1,1) NOT NULL,
    username           VARCHAR(50)  NOT NULL,
    password_hash      VARCHAR(255) NOT NULL,
    role_id            TINYINT      NOT NULL,
    status             TINYINT      NOT NULL CONSTRAINT DF_SysAccount_status DEFAULT 1,
    failed_login_count SMALLINT     NOT NULL CONSTRAINT DF_SysAccount_fail DEFAULT 0,
    locked_until       DATETIME2(3) NULL,
    last_login_at      DATETIME2(3) NULL,
    created_at         DATETIME2(3) NOT NULL CONSTRAINT DF_SysAccount_created DEFAULT SYSDATETIME(),
    updated_at         DATETIME2(3) NOT NULL CONSTRAINT DF_SysAccount_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_SysAccount PRIMARY KEY (account_id),
    CONSTRAINT UQ_SysAccount_01 UNIQUE (username),
    CONSTRAINT CK_SysAccount_status CHECK (status IN (0,1)),
    CONSTRAINT CK_SysAccount_fail CHECK (failed_login_count >= 0)
);

-- ---------- 3. StaffProfile ----------
CREATE TABLE dbo.StaffProfile (
    staff_id            VARCHAR(20)  NOT NULL,
    account_id          BIGINT       NOT NULL,
    employee_no         VARCHAR(30)  NOT NULL,
    staff_name          NVARCHAR(50) NOT NULL,
    gender              VARCHAR(10)  NOT NULL,
    birth_date          DATE         NOT NULL,
    phone_ciphertext    VARBINARY(256) NULL,
    department_name     NVARCHAR(50) NULL,
    employment_status   VARCHAR(20)  NOT NULL,
    hire_date           DATE         NULL,
    created_at          DATETIME2(3) NOT NULL CONSTRAINT DF_StaffProfile_created DEFAULT SYSDATETIME(),
    updated_at          DATETIME2(3) NOT NULL CONSTRAINT DF_StaffProfile_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_StaffProfile PRIMARY KEY (staff_id),
    CONSTRAINT UQ_StaffProfile_01 UNIQUE (account_id),
    CONSTRAINT UQ_StaffProfile_02 UNIQUE (employee_no),
    CONSTRAINT CK_StaffProfile_gender CHECK (gender IN ('MALE','FEMALE','OTHER','UNKNOWN')),
    CONSTRAINT CK_StaffProfile_status CHECK (employment_status IN ('ACTIVE','LEAVE','RESIGNED'))
);

-- ---------- 4. UserProfile ----------
CREATE TABLE dbo.UserProfile (
    user_id           VARCHAR(20)  NOT NULL,
    account_id        BIGINT       NOT NULL,
    real_name         NVARCHAR(50) NULL,
    phone_ciphertext  VARBINARY(256) NOT NULL,
    phone_hash        CHAR(64)     NOT NULL,
    real_name_status  VARCHAR(20)  NOT NULL,
    register_channel  VARCHAR(30)  NULL,
    registered_at     DATETIME2(3) NOT NULL,
    status            VARCHAR(20)  NOT NULL,
    created_at        DATETIME2(3) NOT NULL CONSTRAINT DF_UserProfile_created DEFAULT SYSDATETIME(),
    updated_at        DATETIME2(3) NOT NULL CONSTRAINT DF_UserProfile_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_UserProfile PRIMARY KEY (user_id),
    CONSTRAINT UQ_UserProfile_01 UNIQUE (account_id),
    CONSTRAINT CK_UserProfile_realname CHECK (real_name_status IN ('UNVERIFIED','VERIFIED','FAILED')),
    CONSTRAINT CK_UserProfile_status CHECK (status IN ('ACTIVE','DISABLED'))
);

-- ---------- 5. EnterpriseProfile ----------
CREATE TABLE dbo.EnterpriseProfile (
    enterprise_id           VARCHAR(20)  NOT NULL,
    account_id              BIGINT       NOT NULL,
    enterprise_name         NVARCHAR(100) NOT NULL,
    credit_code             VARCHAR(18)  NOT NULL,
    contact_name            NVARCHAR(50) NOT NULL,
    contact_phone_ciphertext VARBINARY(256) NOT NULL,
    status                  VARCHAR(20)  NOT NULL,
    created_at              DATETIME2(3) NOT NULL CONSTRAINT DF_EnterpriseProfile_created DEFAULT SYSDATETIME(),
    updated_at              DATETIME2(3) NOT NULL CONSTRAINT DF_EnterpriseProfile_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_EnterpriseProfile PRIMARY KEY (enterprise_id),
    CONSTRAINT UQ_EnterpriseProfile_01 UNIQUE (account_id),
    CONSTRAINT UQ_EnterpriseProfile_02 UNIQUE (credit_code),
    CONSTRAINT CK_EnterpriseProfile_status CHECK (status IN ('PENDING','ACTIVE','DISABLED'))
);

-- ---------- 6. SysPermission ----------
CREATE TABLE dbo.SysPermission (
    permission_id   BIGINT IDENTITY(1,1) NOT NULL,
    permission_code VARCHAR(80)  NOT NULL,
    permission_name NVARCHAR(100) NOT NULL,
    module_code     VARCHAR(30)  NOT NULL,
    action_code     VARCHAR(30)  NOT NULL,
    description     NVARCHAR(255) NULL,
    status          TINYINT      NOT NULL CONSTRAINT DF_SysPermission_status DEFAULT 1,
    created_at      DATETIME2(3) NOT NULL CONSTRAINT DF_SysPermission_created DEFAULT SYSDATETIME(),
    updated_at      DATETIME2(3) NOT NULL CONSTRAINT DF_SysPermission_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_SysPermission PRIMARY KEY (permission_id),
    CONSTRAINT UQ_SysPermission_01 UNIQUE (permission_code),
    CONSTRAINT CK_SysPermission_status CHECK (status IN (0,1))
);

-- ---------- 7. RolePermission ----------
CREATE TABLE dbo.RolePermission (
    role_id       TINYINT NOT NULL,
    permission_id BIGINT  NOT NULL,
    data_scope    VARCHAR(20) NOT NULL,
    status        TINYINT NOT NULL CONSTRAINT DF_RolePermission_status DEFAULT 1,
    created_at    DATETIME2(3) NOT NULL CONSTRAINT DF_RolePermission_created DEFAULT SYSDATETIME(),
    updated_at    DATETIME2(3) NOT NULL CONSTRAINT DF_RolePermission_updated DEFAULT SYSDATETIME(),
    CONSTRAINT PK_RolePermission PRIMARY KEY (role_id, permission_id),
    CONSTRAINT CK_RolePermission_scope CHECK (data_scope IN ('ALL','ASSIGNED','SELF','ENTERPRISE','PUBLIC')),
    CONSTRAINT CK_RolePermission_status CHECK (status IN (0,1))
);

-- ---------- 8. OperationLog ----------
CREATE TABLE dbo.OperationLog (
    log_id           BIGINT IDENTITY(1,1) NOT NULL,
    module_code      VARCHAR(30)  NOT NULL,
    object_type      VARCHAR(40)  NOT NULL,
    object_id        VARCHAR(50)  NOT NULL,
    action_code      VARCHAR(50)  NOT NULL,
    actor_type       VARCHAR(10)  NOT NULL,
    actor_account_id BIGINT       NULL,
    occurred_at      DATETIME2(3) NOT NULL,
    before_data      NVARCHAR(MAX) NULL,
    after_data       NVARCHAR(MAX) NULL,
    reason           NVARCHAR(500) NULL,
    CONSTRAINT PK_OperationLog PRIMARY KEY (log_id),
    CONSTRAINT CK_OperationLog_actor CHECK (actor_type IN ('HUMAN','SYSTEM')),
    CONSTRAINT CK_OperationLog_before_json CHECK (before_data IS NULL OR ISJSON(before_data) = 1),
    CONSTRAINT CK_OperationLog_after_json  CHECK (after_data  IS NULL OR ISJSON(after_data)  = 1)
);

-- ---------- 9. ServiceCaseAssignment ----------
CREATE TABLE dbo.ServiceCaseAssignment (
    case_assignment_id  BIGINT IDENTITY(1,1) NOT NULL,
    case_type           VARCHAR(30) NOT NULL,
    case_id             VARCHAR(50) NOT NULL,
    assigned_account_id BIGINT      NOT NULL,
    assigned_by         BIGINT      NOT NULL,
    effective_from      DATETIME2(3) NOT NULL,
    effective_to        DATETIME2(3) NULL,
    CONSTRAINT PK_ServiceCaseAssignment PRIMARY KEY (case_assignment_id),
    CONSTRAINT CK_ServiceCaseAssignment_type CHECK (case_type IN ('ORDER_EXCEPTION','REFUND','PERSONAL_INVOICE','ENTERPRISE_BILL','SETTLEMENT_GENERATE'))
);
GO
