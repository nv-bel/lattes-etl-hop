# Lattes ETL - Apache HOP

Pipeline de dados para extração, transformação e carga (ETL) de Currículos Lattes utilizando Apache HOP e PostgreSQL via Docker.

## Estrutura do Projeto

```
lattes-etl-hop/
├── data/
│   ├── bronze/          # Arquivos XML brutos do Lattes
│   └── silver/          # Dados processados (Parquet)
├── utils/
│   ├── query_sql/       # Scripts SQL
│   └── Treinamento_HOP_Final.pdf
├── hop/                 # Pipelines e workflows do Apache HOP
├── power_bi/            # Dashboard Power BI
├── dockerfile           # Imagem Docker do PostgreSQL
└── init_db.sh           # Script de inicialização do banco
```

## Pré-requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Apache HOP](https://hop.apache.org/)
- [pgAdmin 4](https://www.pgadmin.org/)
- [Power BI Desktop](https://powerbi.microsoft.com/)

## Configuração do Banco de Dados

### 1. Build e start do container

```bash
docker build -t docker_simcc .
docker run -d --name docker_simcc -p 5437:5432 docker_simcc
```

### 2. Conexão no pgAdmin 4

| Campo    | Valor          |
|----------|----------------|
| Host     | 127.0.0.1      |
| Porta    | 5437           |
| Usuário  | postgres       |
| Banco    | BD_PESQUISADOR |

### 3. Criação das tabelas

No pgAdmin 4, abra o **Query Tool** no banco `BD_PESQUISADOR` e execute:

```sql
CREATE EXTENSION "uuid-ossp";

CREATE TABLE IF NOT EXISTS pesquisadores (
  pesquisadores_id UUID NOT NULL DEFAULT uuid_generate_v4(),
  lattes_id VARCHAR(16) NOT NULL,
  nome VARCHAR(200) NOT NULL,
  PRIMARY KEY (pesquisadores_id)
);

CREATE TABLE IF NOT EXISTS producoes (
  producoes_id UUID NOT NULL DEFAULT uuid_generate_v4(),
  pesquisadores_id UUID NOT NULL,
  issn VARCHAR(16) NOT NULL,
  titulo_artigo TEXT NOT NULL,
  ano_artigo INTEGER NOT NULL,
  PRIMARY KEY (producoes_id),
  CONSTRAINT fkey FOREIGN KEY (pesquisadores_id)
    REFERENCES pesquisadores (pesquisadores_id)
    ON UPDATE NO ACTION ON DELETE NO ACTION
);
```

## Pipelines Apache HOP

| Pipeline | Descrição |
|----------|-----------|
| `pesquisador.hpl`    | Extrai dados de um único XML do Lattes |
| `pesquisadores.hpl`  | Extrai dados de múltiplos XMLs |
| `producoes.hpl`      | Extrai artigos indexados e carrega na tabela `producoes` |

### Pesquisadores
![Pipeline Pesquisadores](hop/pesquisadores.png)

### Producoes
![Pipeline Producoes](hop/producoes.png)

### Configuração da conexão no HOP

- **Connection type**: PostgreSQL
- **Host**: 127.0.0.1
- **Port**: 5437
- **Database**: BD_PESQUISADOR
- **Username**: postgres

## Resultado

Dashboard interativo no Power BI conectado diretamente ao PostgreSQL, com filtro de ano (2007–2024) e os seguintes visuais:

- **Top 1 Pesquisador com mais Artigos Publicados** — card com destaque para o pesquisador líder
- **Evolução de Publicações por Ano** — gráfico de linha com tendência histórica
- **Quantidade de Artigos por Ano** — gráfico de barras clusterizado por pesquisador
- **Publicações por Pesquisador** — gráfico de rosca com percentual por pesquisador

Pesquisadores analisados: **Hugo Saba Pereira Cardoso** (51,72%) e **Eduardo Manuel de Freitas Jorge** (48,28%).

![Tela do Dashboard](power_bi/tela_bi.png) 