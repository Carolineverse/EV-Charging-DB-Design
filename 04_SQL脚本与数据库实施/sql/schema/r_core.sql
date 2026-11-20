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
