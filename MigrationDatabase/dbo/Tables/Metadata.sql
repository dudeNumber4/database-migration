CREATE TABLE [dbo].[Metadata] (
    [Id]    INT           IDENTITY (1, 1) NOT NULL,
    [Name]  NVARCHAR (50) NOT NULL,
    [Value] INT           NOT NULL,
    CONSTRAINT [PK_Metadata] PRIMARY KEY CLUSTERED ([Id] ASC)
);

