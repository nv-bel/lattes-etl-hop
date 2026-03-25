CREATE EXTENSION "uuid-ossp";

CREATE TABLE IF NOT EXISTS pesquisadores (
    pesquisadores_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    lattes_id VARCHAR(16) NOT NULL,
    nome_pesquisador VARCHAR(200) NOT NULL,
    PRIMARY KEY (pesquisadores_id));

CREATE TABLE IF NOT EXISTS producoes (
    producoes_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    pesquisadores_id UUID NOT NULL,
    issn VARCHAR(16) NOT NULL,
    titulo_artigo TEXT NOT NULL,
    ano_artigo INTEGER NOT NULL,
    PRIMARY KEY (producoes_id),
    CONSTRAINT fkey FOREIGN KEY (pesquisadores_id)
    REFERENCES pesquisadores (pesquisadores_id) ON UPDATE NO ACTION ON DELETE NO ACTION);
