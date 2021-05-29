if not exists(select 1 from sys.tables where [name] = 'MigrationsJournal')
CREATE TABLE [dbo].[MigrationsJournal] (
    [Id]               INT            IDENTITY (1, 1) NOT NULL,
    [ScriptNumber]     int NOT NULL,
    [AppliedAttempted] DATETIME       CONSTRAINT [DF_MigrationsJournal_Applied] DEFAULT (getdate()) NOT NULL,
    [AppliedCompleted] BIT            CONSTRAINT [DF_MigrationsJournal_AppliedCompleted] DEFAULT ((0)) NOT NULL, 
    [ScriptApplied] VARCHAR(MAX) NULL, 
    [Msg] VARCHAR(MAX) NULL,
	[SchemaChanged] BIT NULL CONSTRAINT [DF_MigrationsJournal_SchemaChanged] DEFAULT (0)
);

go

-- SchemaChanged col added later, add if table already exists
if not exists
(
	select 1 from sys.columns c
		inner join sys.tables t on c.object_id = t.object_id
	where c.[name] = 'SchemaChanged'
		and t.[name] = 'MigrationsJournal'
)
alter table MigrationsJournal add [SchemaChanged] BIT NULL DEFAULT (0)
