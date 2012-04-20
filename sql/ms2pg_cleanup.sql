--------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------
/*

This script cleans up all the objects created by mssql_export_tools.sql

*/
--------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------

if exists (select * from sys.views where object_id = object_id('[dbo].[table_info]'))
begin
	drop view [dbo].[table_info]
end
go

if exists (select * from sys.views where object_id = object_id('[dbo].[index_info]'))
begin
	drop view [dbo].[index_info] 
end
go 

if exists (select * from sys.views where object_id = object_id('[dbo].[fk_info]'))
begin
	drop view [dbo].[fk_info]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_translate_type]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_translate_type]
end
go 

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_translate_default]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_translate_default]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_nullable]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_nullable]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_quote]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_quote]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_comma]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_comma]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_table_def]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_table_def]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_tables]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_tables]
end
go 

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_drop_tables]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_drop_tables]
end
go 

if exists (select * from sys.objects where object_id = object_id('[dbo].[index_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[index_col_list]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_index_create]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_index_create]
end
go 

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_indexes]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_indexes]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[fk_fk_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[fk_fk_col_list]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[fk_pk_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[fk_pk_col_list]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_table_col_list]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_table_col_list]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_fk_create]')
	and type in ('fn', 'if','tf', 'fs', 'ft'))
begin
	drop function [dbo].[pg_fk_create]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_fks]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_fks]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_print_ddl]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_print_ddl]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_print_all_ddl]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_print_all_ddl]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_get_export_commands]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_get_export_commands]
end
go

if exists (select * from sys.objects where object_id = object_id('[dbo].[pg_print_export_commands]') and type in ('p', 'pc'))
begin
	drop procedure [dbo].[pg_print_export_commands]
end
go
