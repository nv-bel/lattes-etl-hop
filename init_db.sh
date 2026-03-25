#!/bin/bash
# Cria o banco de dados
psql -U postgres -d postgres -c "CREATE DATABASE BD_PESQUISADOR
 WITH
 OWNER = postgres
 ENCODING = 'UTF8'
 LC_COLLATE = 'en_US.utf8'
 LC_CTYPE = 'en_US.utf8'
 TABLESPACE = pg_default
 CONNECTION LIMIT = -1
 IS_TEMPLATE = False;"
