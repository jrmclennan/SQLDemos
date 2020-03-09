/**************************************************************************************************
Demo: File Table / File Stream with TDE

Requirements
	SQL Server 2017, may work with other version after 2008, but not tested.
	A single image file to test. One should have been included in the same repository.

References
	https://docs.microsoft.com/en-us/sql/relational-databases/blob/filestream-sql-server?view=sql-server-2017
	https://docs.microsoft.com/en-us/sql/relational-databases/security/encryption/transparent-data-encryption?view=sql-server-2017

**************************************************************************************************/

------------------------------
-- Enable
------------------------------
EXEC sp_configure filestream_access_level, 2  
RECONFIGURE
GO

EXEC sp_configure filestream_access_level 
GO
RETURN



------------------------------
-- Create database
------------------------------
DROP DATABASE IF EXISTS [FileStreamDemo];
GO

-- For this demo use the data folder from the master database and update the file paths.
/*
SELECT	SUBSTRING(physical_name, 1,
		CHARINDEX(N'master.mdf',
		LOWER(physical_name)) - 1) DataFileLocation
FROM	master.sys.master_files
WHERE	database_id = 1 AND FILE_ID = 1
*/
CREATE DATABASE [FileStreamDemo]
CONTAINMENT = NONE
ON PRIMARY 
	(NAME = N'FileStreamDemo', 
	FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL14.INS1\MSSQL\DATA\FileStreamDemo.mdf'	),
FILEGROUP FileStreamGroup1 CONTAINS FILESTREAM
	(NAME = FS1,
    FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL14.INS1\MSSQL\DATA\FileStreamDemo1'	)
LOG ON 
	(NAME = N'FileStreamDemo_log', 
	FILENAME = N'C:\Program Files\Microsoft SQL Server\MSSQL14.INS1\MSSQL\DATA\FileStreamDemo_log.ldf'	)
GO


------------------------------
-- Create file table
------------------------------
USE [master]
GO
ALTER DATABASE [FileStreamDemo] 
SET FILESTREAM(NON_TRANSACTED_ACCESS = FULL, DIRECTORY_NAME = N'DocumentTable' ) WITH NO_WAIT
GO

DROP TABLE IF EXISTS [FileStreamDemo].[dbo].[DocumentStore]  

CREATE TABLE [FileStreamDemo].[dbo].[DocumentStore] AS FileTable  
WITH (   
	FileTable_Directory = 'DocumentTable',  
	FileTable_Collate_Filename = database_default  
);  
GO



------------------------------
-- Insert a file
------------------------------
DECLARE @img AS VARBINARY(MAX)
SELECT @img = CAST(BulkColumn AS VARBINARY(MAX)) -- select *
FROM OPENROWSET(BULK 'C:\Users\jorussel\OneDrive - Microsoft\Documents\Demos\FileStreamDemo\clyde.jpg', SINGLE_BLOB ) AS x

INSERT INTO [FileStreamDemo].[dbo].[DocumentStore] 
(name, file_stream)
SELECT 'clyde.jpg', @img
 

SELECT * FROM [FileStreamDemo].[dbo].[DocumentStore]


------------------------------
-- View
-- \\\MININT-CRVFHAB\INS1_FSShare\DocumentTable\DocumentTable
------------------------------



------------------------------
-- Create the master key and certificate
------------------------------
USE master;  
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Msft!SqlServer';  
GO

CREATE CERTIFICATE CertForTdeDemo WITH SUBJECT = 'DEK Certificate for TDE Demo';  
GO  


------------------------------
-- View databases and certificates
------------------------------
USE [master];  
GO

SELECT	[name], [is_master_key_encrypted_by_server], [is_encrypted]
FROM	sys.databases 
WHERE	[name] IN ('master', 'FileStreamDemo');
GO

SELECT	*
FROM	sys.certificates
WHERE	[name] = 'CertForTdeDemo';
GO


------------------------------
-- Create the certificates
------------------------------
USE [FileStreamDemo]
GO  

CREATE DATABASE ENCRYPTION KEY  
WITH ALGORITHM = AES_128  
ENCRYPTION BY SERVER CERTIFICATE CertForTdeDemo;  
GO  

ALTER DATABASE [FileStreamDemo] 
SET ENCRYPTION ON;  
GO



------------------------------
-- View databases and certificates, again
------------------------------
USE [master];  
GO

SELECT	[name], [is_master_key_encrypted_by_server], [is_encrypted]
FROM	sys.databases 
WHERE	[name] IN ('master', 'FileStreamDemo');
GO

SELECT	*
FROM	sys.certificates
WHERE	[name] = 'CertForTdeDemo';
GO



------------------------------
--Back up the certificate and keys
------------------------------
/*
For this demo, use your data folder.

SELECT	SUBSTRING(physical_name, 1,
		CHARINDEX(N'master.mdf',
		LOWER(physical_name)) - 1) DataFileLocation
FROM	master.sys.master_files
WHERE	database_id = 1 AND FILE_ID = 1;


NOTE: 
The passwords here are weak and we will use the same one for everything.
If you ran this demo on this machine before, you may have to move or delete the existing keys and certs.
*/
USE [master];
GO

BACKUP SERVICE MASTER KEY 
TO FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.INS1\MSSQL\DATA\FileTableTDEDemo_SvcMstKeyBackup.key'
ENCRYPTION BY PASSWORD = 'Msft!SqlServer';

BACKUP MASTER KEY 
TO FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.INS1\MSSQL\DATA\FileTableTDEDemo_DbMstKeyBackup.key'
ENCRYPTION BY PASSWORD = 'Msft!SqlServer';

BACKUP CERTIFICATE CertForTdeDemo 
TO FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.INS1\MSSQL\DATA\FileTableTDEDemoCert.cer'
WITH PRIVATE KEY(
   FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL14.INS1\MSSQL\DATA\FileTableTDEDemoCert.key',
   ENCRYPTION BY PASSWORD = 'Msft!SqlServer'
);

------------------------------
-- Query user database. Notice no extra work is needed to decrypt.
------------------------------
USE [FileStreamDemo]
GO  

SELECT *
FROM [dbo].[DocumentStore];
GO


------------------------------
-- Transparent Data Encryption and Transaction Logs
------------------------------
/* 
Dynamic management view that provides information about the encryption keys used in a database, 
and the state of encryption of a database.

Enabling a database to use TDE has the effect of "zeroing out" the remaining part of the virtual 
transaction log to force the next virtual transaction log. This guarantees that no clear text is 
left in the transaction logs after the database is set for encryption. You can find the status 
of the log file encryption by viewing the encryption_state column in the 
sys.dm_database_encryption_keys view, as in this example:

The value 3 represents an encrypted state on the database and transaction logs. 

0 = No database encryption key present, no encryption
1 = Unencrypted
2 = Encryption in progress
3 = Encrypted
4 = Key change in progress
5 = Decryption in progress
6 = The certificate or asymmetric key encrypting the DEK is being changed
*/  
USE [FileStreamDemo]
GO  

SELECT DB_NAME(database_id), *  
FROM sys.dm_database_encryption_keys  
WHERE [encryption_state] = 3;  
GO 


------------------------------
-- Clean up
------------------------------

-- Turn TDE off
USE [FileStreamDemo]
GO  
ALTER DATABASE [FileStreamDemo] 
SET ENCRYPTION OFF;  
GO

-- Ensure state = 1
SELECT DB_NAME(database_id) AS DatabaseName, [encryption_state]
FROM sys.dm_database_encryption_keys;  
GO  

-- Drop user database key
DROP DATABASE ENCRYPTION KEY;  
GO  

-- Drop certificate and master key
USE [master];  
GO
DROP CERTIFICATE CertForTdeDemo 

DROP MASTER KEY 


-- View databases and certificates
USE [master];  
GO

SELECT	[name], [is_master_key_encrypted_by_server], [is_encrypted]
FROM	sys.databases 
WHERE	[name] IN ('master', 'FileStreamDemo');
GO

SELECT	*
FROM	sys.certificates
WHERE	[name] = 'CertForTdeDemo';
GO


