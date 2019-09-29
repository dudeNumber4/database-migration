-- This table is here in the project so we can ensure it's the first script ever run.
-- We can't just seed the resource file with it, because we have to add the "use DatabaseName" portion that gets added by CommitDatabaseScripts.ps1.
-- It's presence is essentially outside the scope of the rest of the database.
CREATE TABLE [dbo].[MigrationsJournal](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[ScriptName] [varchar](1024) NOT NULL,
	[AppliedAttempted] [datetime] NOT NULL,
	[AppliedCompleted] [bit] NOT NULL
) ON [PRIMARY]

ALTER TABLE [dbo].[MigrationsJournal] ADD  CONSTRAINT [DF_MigrationsJournal_Applied]  DEFAULT (getdate()) FOR [AppliedAttempted]

ALTER TABLE [dbo].[MigrationsJournal] ADD  CONSTRAINT [DF_MigrationsJournal_AppliedCompleted]  DEFAULT ((0)) FOR [AppliedCompleted]
