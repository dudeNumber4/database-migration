-- patch if legacy
if exists
(
	select 1 from sys.columns c
		inner join sys.tables t on c.object_id = t.object_id
	where c.[name] = 'ScriptName'
		and t.[name] = 'MigrationsJournal'
)
begin
  -- Started out as string column with nothing but a number in it.
	alter table MigrationsJournal alter column ScriptName int not null
	exec sp_rename 'MigrationsJournal.ScriptName', 'ScriptNumber', 'COLUMN' 
end

go

if not exists(select 1 from sys.tables where [name] = 'MigrationsJournal')
CREATE TABLE [dbo].[MigrationsJournal] (
    [Id]               INT            IDENTITY (1, 1) NOT NULL,
    [ScriptNumber]     int NOT NULL,
    [AppliedAttempted] DATETIME       CONSTRAINT [DF_MigrationsJournal_Applied] DEFAULT (getdate()) NOT NULL,
    [AppliedCompleted] BIT            CONSTRAINT [DF_MigrationsJournal_AppliedCompleted] DEFAULT ((0)) NOT NULL, 
    [ScriptApplied] VARCHAR(MAX) NULL, 
    [Msg] VARCHAR(MAX) NULL
);