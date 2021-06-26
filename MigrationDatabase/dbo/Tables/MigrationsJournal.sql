CREATE TABLE [dbo].[MigrationsJournal] (
    [Id]               INT           IDENTITY (1, 1) NOT NULL,
    [ScriptNumber]     INT           NOT NULL,
    [AppliedAttempted] DATETIME      CONSTRAINT [DF_MigrationsJournal_Applied] DEFAULT (getdate()) NOT NULL,
    [AppliedCompleted] BIT           CONSTRAINT [DF_MigrationsJournal_AppliedCompleted] DEFAULT ((0)) NOT NULL,
    [ScriptApplied]    VARCHAR (MAX) NULL,
    [Msg]              VARCHAR (MAX) NULL, 
    [SchemaChanged] BIT NULL CONSTRAINT [DF_MigrationsJournal_SchemaChanged] DEFAULT (0)
);
