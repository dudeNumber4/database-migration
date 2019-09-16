CREATE TABLE [dbo].[MigrationsJournal] (
    [Id]               INT            IDENTITY (1, 1) NOT NULL,
    [ScriptName]       VARCHAR (1024) NOT NULL,
    [AppliedAttempted] DATETIME       CONSTRAINT [DF_MigrationsJournal_Applied] DEFAULT (getdate()) NOT NULL,
    [AppliedCompleted] BIT            CONSTRAINT [DF_MigrationsJournal_AppliedCompleted] DEFAULT ((0)) NOT NULL
);



