# Use a imagem oficial do pgvector
FROM pgvector/pgvector:pg17
# Variáveis de ambiente para o PostgreSQL
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=123456
ENV POSTGRES_DB=BD_PESQUISADOR
ENV POSTGRES_HOST_AUTH_METHOD=trust
# Copie o arquivo script de inicialização para o container
COPY init_db.sh /docker-entrypoint-initdb.d/init_db.sh
# Concede permissão de execução ao script de inicialização
RUN chmod +x /docker-entrypoint-initdb.d/init_db.sh
# Expõe a porta 5437
EXPOSE 5437
