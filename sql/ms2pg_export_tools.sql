-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
/*

This script provides a series of tools for exporting tables, indexes and 
foreign keys from SQL Server to Postgres.

After running this script to create the necessary objects in your SQL Server 
database, you can use this in one of two ways:

1. When connecting programmatically from a client application, the following 
   commands will give you the DDL statements to reproduce SQL Server objects 
   in your Postgres database:

   * exec pg_get_tables <catalog>
     Returns DDL statements to create all tables in the specified SQL Server 
     catalog.

   * exec pg_get_indexes <catalog>
     Returns DDL statements to create all indexes in the specified SQL Server 
     catalog.

   * exec pg_get_fks <catalog>
     Returns DDL statements to create all foreign keys in the specified 
     SQL Server catalog.

   In addition, the following two stored procedures are available:

   * exec pg_drop_tables <catalog>
     Returns DDL statements to drop all tables in the specified SQL Server 
     catalog.

   * exec pg_get_export_commands <catalog> <user> <password> <server>
     Returns export commands to dump data into flat text files from all 
     tables in the specified SQL Server catalog. These commands must be 
     run from a batch file.

2. When using SQL Server Management Studio, you can dump DDL statements 
   and export  commands directly to the output window with the following 
   commands:

   * exec dbo.pg_print_all_ddl <catalog>

   * exec dbo.pg_print_export_commands <catalog> <user> <password> <server>

Each of the stored procedures below is documented, in case you need help 
understanding the parameters and output.

When you're done, you can remove all of the objects this script created by 
running the accompanying script called mssql_export_cleanup.sql.

*/
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

--
-- table_info
--
-- This view provides information about tables and columns.
-- It includes all of the information necessary to generate
-- the CREATE TABLE ddl statements for each table in the 
-- database.
--
if exists (select * from sys.views where object_id = object_id('[dbo].[table_info]'))
begin
	drop view [dbo].[table_info]
end
go

create view [dbo].[table_info] as
select	c.table_catalog, 
		c.table_schema, 
		c.table_name, 
		c.column_name, 
		c.ordinal_position, 
		c.column_default, 
		c.is_nullable, 
		c.data_type, 
		c.character_maximum_length, 
		c.numeric_precision, 
		c.numeric_scale,
		t.table_type,
		coalesce((select i.is_primary_key 
			from
			sys.columns sc 
			inner join sys.index_columns ic ON ic.object_id = sc.object_id AND ic.column_id = sc.column_id
			inner join sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
			where sc.object_id = object_id(c.table_name) and sc.name = c.column_name and i.is_primary_key = 1
		 ), 0) as is_primary_key,
		coalesce((select sc.is_identity 
			from
			sys.columns sc 
			where sc.object_id = object_id(c.table_name) and sc.name = c.column_name and sc.is_identity = 1
		 ), 0) as is_identity
from information_schema.columns c 
inner join information_schema.tables t on t.table_name = c.table_name
go

-------------------------------------------------------------------------------

--
-- index_info
-- 
-- This view contains all of the information necessary for generating
-- CREATE INDEX statements.
--
-- Based on a query by Marc S at
-- http://stackoverflow.com/questions/765867/list-of-all-index-index-columns-in-sql-server-db
--
if exists (select * from sys.views where object_id = object_id('[dbo].[index_info]'))
begin
	drop view [dbo].[index_info] 
end
go 
 
create view [dbo].[index_info] as
select 
    ind.name as index_name,
	t.name as table_name,
    col.name as column_name,
    ind.index_id, 
    ic.index_column_id, 
	ind.type_desc, 
	ind.is_unique,
	ind.is_unique_constraint,
	col.max_length,
	col.is_nullable,
	col.is_identity,
	col.is_computed
from sys.indexes ind 
inner join sys.index_columns ic 
    on ind.object_id = ic.object_id and ind.index_id = ic.index_id 
inner join sys.columns col 
    on ic.object_id = col.object_id and ic.column_id = col.column_id 
inner join sys.tables t 
    on ind.object_id = t.object_id 
where ind.is_primary_key = 0 and t.is_ms_shipped = 0 
go

-------------------------------------------------------------------------------

--
-- fk_info
--
-- This view contains all of the info necessary for generating
-- foreign key statements.
--
-- The underlying query comes from Dave Pinal
-- http://blog.sqlauthority.com/2006/11/01/sql-server-query-to-display-foreign-key-relationships-and-name-of-the-constraint-for-each-table-in-database/
--
if exists (select * from sys.views where object_id = object_id('[dbo].[fk_info]'))
begin
	drop view [dbo].[fk_info]
end
go

create view [dbo].[fk_info] as
select fk.table_name as fk_table,
	   cu.column_name as fk_column,
       pk.table_name as pk_table,
       pt.column_name as pk_column,
       c.constraint_name
from information_schema.referential_constraints c
inner join information_schema.table_constraints fk on c.constraint_name = fk.constraint_name
inner join information_schema.table_constraints pk on c.unique_constraint_name = pk.constraint_name
inner join information_schema.key_column_usage cu on c.constraint_name = cu.constraint_name
inner join (
    select i1.table_name, i2.column_name
    from information_schema.table_constraints i1
    inner join information_schema.key_column_usage i2 on i1.constraint_name = i2.constraint_name
    where i1.constraint_type = 'primary key'
) pt on pt.table_name = pk.table_name
go

-------------------------------------------------------------------------------
--
-- pg_translate_type
--
-- Translates a SQL Server data type to a Postgres data type.
-- For example, given nvarchar(80) returns varchar(80).
-- This covers most types, but not all.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_translate_type]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_translate_type]
end
go 

create function [dbo].[pg_translate_type](	@data_type varchar(50),
											@length int,
											@precision int,
											@scale int,
											@is_primary_key bit,
											@is_identity bit,
											@primary_key_count int)
returns varchar(200)
as 
begin
	return
		(case
			-- Translate int primary key to serial primary key. However,
			-- if we have an int column that is part of a composite primary 
            -- key, we must not mark it as the primary key. Composite keys 
			-- are common in join tables, and in those cases they are never 
			-- serial/auto_increment.
			when @data_type = 'int' and (@is_primary_key = 1 or @is_identity = 1) and @primary_key_count = 1 then ' serial primary key'
			when @data_type = 'tinyint' then 'smallint'
			when @data_type = 'bit' then 'bool'
			when @data_type = 'datetime' then 'timestamp'
			when @data_type = 'uniqueidentifier' then 'uuid'
			when @data_type = 'nvarchar' then 'varchar'
			when @data_type = 'nchar' then 'char'
			when @data_type = 'ntext' then 'text'
			when @data_type = 'money' then 'numeric'
			when @data_type = 'decimal' then 'numeric'
			when @data_type = 'float' then 'double precision'			
			when @data_type = 'image' then 'bytea'
			else @data_type
		end	+ 
		case 
			when @data_type = 'image' or @data_type = 'text' or @data_type = 'ntext' then ''
			when @length is not null then '(' + CAST(@length as varchar(10)) + ')'
			else ''
		end + 
		case 
			when @data_type != 'int' and @precision is not null and @scale is not null then 
				' (' + CAST(@precision as varchar(10)) + ',' + CAST(@scale as varchar(10)) + ')'
			else ''
		end)
end
go


-------------------------------------------------------------------------------

--
-- pg_translate_default
--
-- Translates a SQL Server column default value to a Postgres default.
-- Returns a string to be used in the Posrgres CREATE TABLE statement.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_translate_default]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_translate_default]
end
go

create function [dbo].[pg_translate_default] (@data_type varchar(80), @column_default varchar(8000))
returns varchar(8000)
as
begin
	return (case 
				-- postgres does not have any built-in analog for newid()
				-- so we set the column to unique, and it's up to you to 
				-- generate a UUID for each insert. This page has a function
				-- for generating UUIDs in Postgres, and shows how to use
				-- that function in a CREATE TABLE statement so that new rows
				-- automatically get new UUIDs:
				--
				-- http://www.codeproject.com/Articles/56562/Creating-newid-for-PostgreSQL
				when @column_default = '(newid())' then ' unique'
				when @column_default = '(getdate())' then ' default now()'
				when @data_type = 'bit' then
					case
						when @column_default = '(1)' then ' default ''t'''
						when @column_default = '(0)' then ' default ''f'''
						else ''
					end
				-- This ugly bit strips off the leading and trailing 
				-- parentheses
				when @column_default is not null then ' default ' + (left(right(@column_default, len(@column_default) - 1), len(@column_default) - 2))
				else ''
			end)
end
go

-------------------------------------------------------------------------------

--
-- pg_nullable
--
-- Returns either 'NULL' or 'NOT NULL' to indicate whether a column allows
-- null values. This is used in generating CREATE TABLE statements.
--

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_nullable]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_nullable]
end
go

create function [dbo].[pg_nullable](@is_nullable varchar(10),
									@is_primary_key bit,
									@is_identity bit)
returns varchar(20)
as
begin
	return
		(case 
			when @is_nullable = 'NO' then ' NOT NULL'
			when  (@is_primary_key = 1 or @is_identity = 1) then ' NOT NULL'
			else ' NULL'
		end) 
end
go

-------------------------------------------------------------------------------

--
-- pg_quote
--
-- Returns the input @value enclosed in double quotes, so that is it becomes a 
-- safe Postgres identifier. 
--

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_quote]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_quote]
end
go

create function [dbo].[pg_quote] (@value varchar(200))
returns varchar(202)
as
begin
	return '"' + @value + '"'
end
go

-------------------------------------------------------------------------------

--
-- pg_comma
--
-- Used to add commas to comma-separated lists. Returns a comma and a space if
-- position < last. That is, if the item you are adding to the list is not the
-- last item in the list.
--

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_comma]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_comma]
end
go

create function [dbo].[pg_comma](@position int, @last int)
returns varchar(2)
as
begin
	return
		(case
			when @position < @last then ', '
			else ''
		end)
end
go

-------------------------------------------------------------------------------

--
-- pg_table_def
--
-- This function returns a CREATE TABLE statement suitable
-- for Postgres. 
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_table_def]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_table_def]
end
go

create function [dbo].[pg_table_def] (@table_name varchar(200)) 
returns varchar(8000)
as
begin
	declare @statement varchar(8000)
	declare @col_def varchar(300)
	declare @max_ordinal int

	set @statement = 'create table ' + dbo.pg_quote(@table_name) + ' ('
	select @max_ordinal = max(ordinal_position) from table_info where table_name = @table_name

	declare col_cursor cursor for
		select 
		dbo.pg_quote(column_name) + 
		' ' + 
		dbo.pg_translate_type(	data_type, 
								character_maximum_length, 
								numeric_precision,
								numeric_scale,
								is_primary_key,
								is_identity,
								-- This query slows the entire script!
								(select count(*) from table_info where table_name = @table_name and is_primary_key = 1)) + 
		dbo.pg_nullable(is_nullable, is_primary_key, is_identity) +
		dbo.pg_translate_default(data_type, column_default) + 
		dbo.pg_comma(ordinal_position, @max_ordinal)
		from table_info 
		where table_name = @table_name 
		order by ordinal_position

	OPEN col_cursor
	FETCH NEXT FROM col_cursor INTO @col_def

	WHILE @@FETCH_STATUS = 0   
	BEGIN   
		set @statement = @statement + ' ' + @col_def
		FETCH NEXT FROM col_cursor INTO @col_def
	END   

	close col_cursor
	deallocate col_cursor

	return @statement + ');'

end
go

-------------------------------------------------------------------------------

--
-- pg_get_tables
--
-- This procedure returns on CREATE TABLE statement for each table
-- in the specified SQL Server catalog.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_tables]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_tables]
end
go 

create procedure [dbo].[pg_get_tables] ( @catalog varchar(100) )
as
begin
	select table_name, dbo.pg_table_def(table_name) as 'sql_statement'
	from information_schema.tables
	where table_catalog = @catalog and table_type = 'BASE TABLE'
	order by table_name
end
go

-------------------------------------------------------------------------------

--
-- pg_drop_tables
-- 
-- This procedure generates a DROP TABLE statement for each
-- table in the specified SQL Server catalog. The drop statements
-- are meant to be run in Postgres, not in SQL Server.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_drop_tables]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_drop_tables]
end
go 

create procedure [dbo].[pg_drop_tables] ( @catalog varchar(100) )
as
begin
	select	table_name,
			'drop table ' + dbo.pg_quote(table_name) + ' cascade;' as 'sql_statement'
	from information_schema.tables
	where table_catalog = @catalog and table_type = 'BASE TABLE'
	order by table_name
end
go

-------------------------------------------------------------------------------

--
-- index_col_list
--
-- This function returns a list of columns as a comma-delimited string,
-- with each column name quoted for Postgres. This is used by 
-- pg_get_indexes to generate CREATE INDEX statements.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[index_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[index_col_list]
end
go

create function [dbo].[index_col_list] (@index_name varchar(200))
returns varchar(8000)
as
begin
	declare @column varchar(200)
	declare @max_ordinal int
	declare @col_index int
	declare @cols varchar(8000)
	set @cols = ''

	select @max_ordinal = max(index_column_id)
	from index_info where index_name = @index_name

	declare col_cursor cursor for
		select column_name, index_column_id 
		from index_info where index_name = @index_name
		order by index_column_id

	open col_cursor
	fetch next from col_cursor into @column, @col_index

	while @@fetch_status = 0   
	begin
		set @cols = @cols + dbo.pg_quote(@column) + dbo.pg_comma(@col_index, @max_ordinal)
		fetch next from col_cursor into @column, @col_index
	end

	close col_cursor
	deallocate col_cursor
	return @cols
end
go

----------------------------------------------------------------------------

--
-- pg_index_create
--
-- Returns a Postgres CREATE INDEX statement for the specified 
-- SQL Server index.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_index_create]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_index_create]
end
go 

create function [dbo].[pg_index_create] (@index_name varchar(200))
returns varchar(8000)
as
begin
	return (select top 1 'create ' +
			case 
				when is_unique = 1 or is_unique_constraint = 1 then ' unique'
				else ''
			end + 
			' index ' + dbo.pg_quote(index_name) + ' on ' + dbo.pg_quote(table_name) + 
			' (' + dbo.index_col_list(index_name) + ');'
			from index_info where index_name = @index_name)
end
go


----------------------------------------------------------------------------

--
-- pg_get_indexes
--
-- Generates a CREATE INDEX statement for each index in the specified
-- SQL Server catalog, except for primary key indexes, which are handled
-- in the CREATE TABLE statements.
--
-- Returns cols 'index_name' and 'sql_statement'.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_indexes]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_indexes]
end
go

create procedure [dbo].[pg_get_indexes] (@catalog varchar(200))
as
begin
	select 
		distinct(index_name), 
		dbo.pg_index_create(index_name) as 'sql_statement'
	from index_info
	where table_name in (select table_name 
						 from information_schema.tables 
						 where table_catalog = @catalog)
	order by index_name
end
go

-------------------------------------------------------------------------------

--
-- fk_fk_col_list
--
-- This function returns a comma-separated list of foreign key column names.
-- Each name is quoted for Postgres.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[fk_fk_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[fk_fk_col_list]
end
go

create function [dbo].[fk_fk_col_list] (@constraint_name varchar(200))
returns varchar(8000)
as
begin
	declare @column varchar(200)
	declare @cols varchar(8000)
	set @cols = ''

	declare col_cursor cursor for
		select fk_column 
		from fk_info where constraint_name = @constraint_name

	open col_cursor
	fetch next from col_cursor into @column

	while @@fetch_status = 0   
	begin
		set @cols = @cols + dbo.pg_quote(@column) + ','
		fetch next from col_cursor into @column
	end

	close col_cursor
	deallocate col_cursor
	return left(@cols, len(@cols) - 1)
end
go


-------------------------------------------------------------------------------

--
-- fk_pk_col_list
--
-- This function returns a comma-separated list of primary key column names
-- that are referenced in foreign keys. Each name is quoted for Postgres.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[fk_pk_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[fk_pk_col_list]
end
go

create function [dbo].[fk_pk_col_list] (@constraint_name varchar(200))
returns varchar(8000)
as
begin
	declare @column varchar(200)
	declare @cols varchar(8000)
	set @cols = ''

	declare col_cursor cursor for
		select pk_column 
		from fk_info where constraint_name = @constraint_name

	open col_cursor
	fetch next from col_cursor into @column

	while @@fetch_status = 0   
	begin
		set @cols = @cols + dbo.pg_quote(@column) + ','
		fetch next from col_cursor into @column
	end

	close col_cursor
	deallocate col_cursor
	return left(@cols, len(@cols) - 1)
end
go

-------------------------------------------------------------------------------

--
-- pg_table_col_list
--
-- Returns comma-separated list of column names for the specified table.
-- If @quote_for = 'sql server', names will be enclosed in brackets.
-- If @quote_for = 'postgres', names will enclosed in double quotes.
-- If @quote_for = 'single', names will enclosed in single quotes.
-- Otherwise, names will not be quoted.
-- 
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_sqlcmd_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_sqlcmd_col_list]
end
go

create function [dbo].[pg_sqlcmd_col_list] (@table_name varchar(200))
returns varchar(8000)
as
begin
	declare @column varchar(200)
	declare @data_type varchar(200)
	declare @max_ordinal int
	declare @col_index int
	declare @cols varchar(8000)
	set @cols = ''

	select @max_ordinal = max(ordinal_position)
	from table_info where table_name = @table_name

	declare col_cursor cursor for
		select column_name, ordinal_position, data_type 
		from table_info where table_name = @table_name
		order by ordinal_position

	open col_cursor
	fetch next from col_cursor into @column, @col_index, @data_type

	while @@fetch_status = 0   
	begin
		set @cols = @cols + '[' + @column + ']' + dbo.pg_comma(@col_index, @max_ordinal)
		fetch next from col_cursor into @column, @col_index, @data_type
	end

	close col_cursor
	deallocate col_cursor
	return @cols
end
go

-------------------------------------------------------------------------------

--
-- pg_fk_create
--
-- Generates a statement to add the specified foreign key to the proper 
-- Postgres table.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_fk_create]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_fk_create]
end
go

create function [dbo].[pg_fk_create] (@fk_name varchar(200))
returns varchar(8000)
as
begin
	return (select top 1
			'alter table ' +
			dbo.pg_quote((select fk_table from fk_info where constraint_name = @fk_name)) +
			' add constraint ' + dbo.pg_quote(@fk_name) + ' foreign key (' +
			dbo.fk_fk_col_list(@fk_name) +
			') references ' + 
			dbo.pg_quote((select pk_table from fk_info where constraint_name = @fk_name)) + 
			' (' + dbo.fk_pk_col_list(@fk_name) + ');')
end
go 


-------------------------------------------------------------------------------

--
-- pg_get_fks
--
-- Generates statements to add foreign keys to tables in the Postgres database.
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_fks]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_fks]
end
go

create procedure [dbo].[pg_get_fks] (@catalog varchar(200))
as
begin
	select 
		distinct(constraint_name) as 'foreign_key',
		dbo.pg_fk_create(constraint_name) as 'sql_statement'
	from fk_info 
	where fk_table in (select table_name 
						 from information_schema.tables 
						 where table_catalog = @catalog)
	order by constraint_name
end
go

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------

--
-- pg_print_ddl
--
-- Prints a set of Postgresql DDL commands to the messages pane in SQL Server 
-- Management Studio. You can then run these commands in Postgres to recreate
-- the SQL Server objects in your Postgres DB.
--
-- Param @catalog is the name of the catalog whose schema you want to export.
-- Param @print_what must be one of the following:
--
-- * 'drop tables'         - Prints a set of DROP TABLE commands to drop 
-- 	 	   				   	 all of the specified catalog's tables from 
--                           the Postgres database. This is handy if something
--							 goes wrong and you want to wipe out the schema 
--							 you just created.
-- * 'create tables'       - Prints a set of CREATE TABLE commands to create 
-- 	 		 			   	 all of the tables in the specified catalog in 
-- 							 the Postgres database.
-- * 'create indexes'      - Prints a set of Postgres-specific CREATE INDEX 
-- 	 		 			   	 commands to create all of the indexes in the 
-- 							 specified catalog.
-- * 'create foreign keys' - Prints a set of Postgres-specific commands to add 
--                           foreign keys to the new tables.

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_print_ddl]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_print_ddl]
end
go

create procedure [dbo].[pg_print_ddl](@print_what varchar(40), @catalog varchar(200))
as
begin

	declare @statement varchar(8000)
	declare @table table (obj_name varchar(200), command varchar(8000))

	set nocount on
	if @print_what = 'drop tables' 
	begin 
		print '-- Drop Tables for catalog ' + @catalog
		insert @table exec dbo.pg_drop_tables @catalog 
	end
	else if @print_what = 'create tables' 
	begin
		print '-- Create Tables for catalog ' + @catalog
		insert @table exec dbo.pg_get_tables @catalog 
	end	
	else if @print_what = 'create indexes' 
	begin 
		print '-- Create Indexes for catalog ' + @catalog
		insert @table exec dbo.pg_get_indexes @catalog 
	end
	else if @print_what = 'create foreign keys' 
	begin 
		print '-- Create Foreign Keys for catalog ' + @catalog
		insert @table exec dbo.pg_get_fks @catalog 
	end
	else begin raiserror('Invalid param @print_what: valid options are "drop tables", "create tables", "create indexes", "create foreign keys"', 16, 1) end

	declare statement_cursor cursor for 
	select command from @table

	open statement_cursor
	fetch next from statement_cursor into @statement

	while @@fetch_status = 0   
	begin
		print @statement
		fetch next from statement_cursor into @statement
	end

	close statement_cursor
	deallocate statement_cursor

end
go

-------------------------------------------------------------------------------

--
-- pg_print_all_ddl
--
-- Prints all of the DDL statements, in the correct order, to re-create the 
-- current SQL Server database in Postgres. All output goes to the SQL Server 
-- Management Studio messages window.
--
-- Obviously, you can skip the DROP TABLE statements when you are first 
-- creating your Postgres database. They are handy, however, for re-creating 
-- the database.
--
-- All of the other commands are printed in the proper order, with tables being
-- created first, followed by indexes, followed by foreign keys. It's easiest 
-- to add the foreign keys last, so that we know all necessary tables and 
-- unique indexes exist when we tell our keys to refer to them.
--

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_print_all_ddl]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_print_all_ddl]
end
go

create procedure [dbo].[pg_print_all_ddl](@catalog varchar(200))
as
begin

	exec dbo.pg_print_ddl 'drop tables', @catalog
	print ''
	print ''
	exec dbo.pg_print_ddl 'create tables', @catalog
	print ''
	print ''
	exec dbo.pg_print_ddl 'create indexes', @catalog
	print ''
	print ''
	exec dbo.pg_print_ddl 'create foreign keys', @catalog

end
go

-------------------------------------------------------------------------------

--
-- pg_get_export_commands
--
-- Produces a series of commands to export data from tables into tab-delimited
-- text files. We use this instead of sqlcmd instead of bcp because bcp has no
-- option to remove control characters (tabs, newlines, etc.), cannot quote
-- text fields, and represents empty strings as null bytes (\0) within the
-- output file -- even when you explicitly specify character output. The null
-- bytes cause imports to fail.
--
-- These export commands will get your data over to Postgres, but note the 
-- following limitations:
--
-- 1. Fields are limited to 65535 characters. If you're exporting text columns
--    with more data than that, they will be truncated.
-- 2. Tabs and newlines are replaced with spaces, which means you will lose 
--    some formatting.
-- 3. Binary data? Hmm. Haven't tried that yet. I bet there will be problems
--    there.
--
-- One other thing to note is that if you try to paste one of these commands
-- into a DOS shell window, the shell will replace the literal tab character
-- with some arbitrary file name. There is no way around this. That means
-- that you MUST run the sqlcmd statements from a batch file.
--
-- -k          Replace control characters (tabs, newlines, etc.) with a space
-- -h -1       Suppress column headers. It would be nice to have these, but
--             sqlcmd adds a line full of dashes in addition to the headers.
-- -w 65535    Allow columns to be this many characters wide.
-- -W          Trims extraneous spaces from the end of each column.
-- -s          Indicates the separator. You must use a literal tab, rather than
--             \t for tab.
-- -l 10       Wait up to 10 seconds when trying to log in, then quit.
-- -d <db>     Name of database catalog to query.
-- -S <server> Name of server host and instance. E.g. LOCALHOST\SQLSERVER2005
-- -U <user>   SQL Server user login
-- -P <pwd>    Password for SQL Server user
-- -f o:65001  Generate UTF-8 output
-- -Q <query>  Literal query to execute. Should be enclosed in double quotes.
--

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_export_commands]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_export_commands]
end
go

create procedure [dbo].[pg_get_export_commands] (@catalog varchar(200),
												@user varchar(200),
												@password varchar(200),
												@server varchar(200))
as
begin
select 'sqlcmd -k -h -1 -w 65535 -W -s "	" -l 10' +
	' -d ' + @catalog + 
	' -S ' + @server + 
	' -U ' + @user + 
	' -P ' + @password + 
	' -f o:65001 ' + 
	' -Q "set nocount on; select ' + 
	dbo.pg_sqlcmd_col_list(table_name) + 
	' from ' + table_name + '" -o ' + table_name + '.txt' 			
FROM information_schema.tables where table_type = 'base table'
order by table_name
end
go

-------------------------------------------------------------------------------

--
-- pg_print_export_commands
--
-- Prints a set of export commands to the SQL Server message window
-- to export data from all tables in the specified catalog.
--
-- Params:
--
-- @catalog   - The name of the catalog whose data you want to export.
-- @user      - The name of the SQL Server user, for sqlcmd to log in.
-- @password  - The password of the SQL Server user, for sqlcmd to log in.
-- @server    - The server and instance for sqlcmd to connect to when 
--              pulling data. The server name and SQL Server instance
--              name should be separated by a backslash. For example,
--              to pull data from the instance SQLSERVER2005 on bigbox,
--              you would specify BIGBOX\SQLSERVER2005
--
if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_print_export_commands]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_print_export_commands]
end
go

create procedure [dbo].[pg_print_export_commands](@catalog varchar(200),
									  @user varchar(200),
									  @password varchar(200),
									  @server varchar(200))
as
begin

	declare @statement varchar(8000)
	declare @table table (command varchar(8000))

	set nocount on
	insert @table exec dbo.pg_get_export_commands @catalog, @user, @password, @server

	declare statement_cursor cursor for 
	select command from @table

	open statement_cursor
	fetch next from statement_cursor into @statement

	while @@fetch_status = 0   
	begin
		print @statement
		fetch next from statement_cursor into @statement
	end

	close statement_cursor
	deallocate statement_cursor
end
go
