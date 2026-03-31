-- =============================================================================
-- BUSCA TEXTUAL COMPLETA (Full Text Search) NO POSTGRESQL
-- Tutorial base: https://www.infoq.com/br/articles/postgresql-fts/
-- Adaptado para as tabelas pesquisadores e producoes do lattes-etl-hop
-- =============================================================================
--
-- Schema do lattes-etl-hop (sem alterações):
--   pesquisadores (pesquisadores_id UUID, lattes_id VARCHAR(16), nome_pesquisador VARCHAR(200))
--   producoes     (producoes_id UUID, pesquisadores_id UUID, issn VARCHAR(16),
--                  titulo_artigo TEXT, ano_artigo INTEGER)
--
-- Correspondência com o tutorial original (author / post / tag / posts_tags):
--   author.name          ~  pesquisadores.nome_pesquisador
--   post.title           ~  producoes.titulo_artigo
--   post.content         →  não existe campo de resumo; o FTS opera só sobre o título
--   tag / posts_tags     →  não existe no schema; issn é apenas um código numérico
--                            e NÃO é utilizado como texto indexável
--
-- Observação sobre idioma: os títulos do corpus são mistos (inglês e português).
-- Por isso a configuração 'simple' é usada como padrão — ela não aplica stemming
-- nem remove stop words, funcionando corretamente para qualquer idioma.
-- As seções 3 e 4 demonstram as alternativas 'english', 'portuguese' e 'pt' (custom).
-- =============================================================================


-- =============================================================================
-- SEÇÃO 0 – EXTENSÕES E DADOS DE EXEMPLO
-- =============================================================================

-- Extensão necessária para geração de UUID (já habilitada no lattes-etl-hop)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Extensão para remoção de acentos (utilizada na Seção 4)
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Extensão para similaridade de strings / correção ortográfica (utilizada na Seção 7)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =============================================================================
-- SEÇÃO 1 – CONSTRUINDO DOCUMENTOS PARA BUSCA
-- Tutorial: "Building Documents"
-- =============================================================================

-- 1.1 – Concatenação simples dos campos textuais formando um único "documento"
--       Equivale ao exemplo do tutorial:  title || content || author_name || tags
--       No nosso caso: titulo_artigo || nome_pesquisador
--       O issn é um código (ex.: '01291831') e não agrega valor semântico
SELECT
    p.titulo_artigo || ' ' || r.nome_pesquisador AS documento
FROM producoes p
JOIN pesquisadores r ON r.pesquisadores_id = p.pesquisadores_id;

-- 1.2 – Conversão do documento para TSVECTOR
--       to_tsvector() normaliza o texto: remove stop words, aplica stemming (se o
--       idioma suportar) e retorna uma lista de lexemas com suas posições no texto.
--       Usamos 'simple' pois o corpus tem títulos em inglês e português misturados.
SELECT
    to_tsvector('simple', p.titulo_artigo)    ||
    to_tsvector('simple', r.nome_pesquisador)  AS documento_tsvector
FROM producoes p
JOIN pesquisadores r ON r.pesquisadores_id = p.pesquisadores_id;

-- 1.3 – Exemplo simples de to_tsvector() com título real do corpus
--       Com 'english': stop words (in, the, of) são removidas, "spreading" → "spread"
--       Com 'simple':  todos os tokens são mantidos sem alteração
SELECT to_tsvector('english', 'Synchronized spread of COVID-19 in the cities of Bahia, Brazil');
-- Resultado: '-19':5 'bahia':10 'brazil':11 'citi':8 'covid':4 'spread':2 'synchron':1
-- *Nota: o hífen faz o PostgreSQL separar 'COVID-19' em dois lexemas: 'covid' e '-19'

SELECT to_tsvector('simple',  'Synchronized spread of COVID-19 in the cities of Bahia, Brazil');
-- Resultado: '-19':5 'bahia':10 'brazil':11 'cities':8 'covid':4 'in':6 'of':3,9 'spread':2 'synchronized':1 'the':7
-- *Nota: 'simple' também separa COVID-19 em 'covid' e '-19', mas mantém stop words (of, in, the)
--       e NÃO aplica stemming: 'cities' permanece 'cities' (vs 'citi' no english)


-- =============================================================================
-- SEÇÃO 2 – REALIZANDO BUSCAS (TSQuery)
-- Tutorial: "Performing Queries"
-- =============================================================================

-- 2.1 – Operador @@ : verifica se um tsvector "casa" com uma tsquery
--       Retorna TRUE se o lexema existir no vetor, FALSE caso contrário
SELECT to_tsvector('simple', 'Self-affinity in the dengue fever time series') @@ 'dengue';
-- Retorna: true  (a palavra existe no vetor)

SELECT to_tsvector('simple', 'Self-affinity in the dengue fever time series') @@ 'covid';
-- Retorna: false  (a palavra não existe neste título)

-- 2.2 – Diferença entre cast direto e to_tsquery()
--       'dengue'::tsquery apenas converte o literal sem normalizar
--       to_tsquery() valida a sintaxe e aplica normalização (stemming se configurado)
SELECT 'dengue'::tsquery, to_tsquery('simple', 'dengue');

SELECT to_tsvector('simple', 'Paradox between adequate sanitation and rainfall in dengue fever cases')
    @@ to_tsquery('simple', 'dengue');
-- Retorna: true

-- 2.3 – Operadores booleanos dentro de to_tsquery()
--       !  = NÃO (NOT)    &  = E (AND)    |  = OU (OR)

-- NOT: títulos que NÃO contenham "dengue"
SELECT to_tsvector('simple', 'Synchronized spread of COVID-19 in the cities of Bahia, Brazil')
    @@ to_tsquery('simple', '! dengue');
-- Retorna: true  (este título não fala de dengue)

-- AND: deve conter "dengue" E não conter "covid"
--      'COVID-19' é tokenizado como 'covid' + '-19'; usar 'covid' como termo de busca
SELECT to_tsvector('simple', 'Self-affinity in the dengue fever time series')
    @@ to_tsquery('simple', 'dengue & ! covid');
-- Retorna: true

-- OR: deve conter "dengue" OU "covid"
SELECT to_tsvector('simple', 'Scaling effect in COVID-19 spreading')
    @@ to_tsquery('simple', 'dengue | covid');
-- Retorna: true  ('COVID-19' foi tokenizado como 'covid' pelo PostgreSQL)

-- 2.4 – Wildcard com :* (busca por prefixo)
--       Encontra qualquer lexema que comece com o prefixo fornecido
SELECT to_tsvector('simple', 'Practices with educational robotics in professional and technological education')
    @@ to_tsquery('simple', 'educat:*');
-- Retorna: true  (encontra 'educational' e 'education')

-- 2.5 – Busca completa nas tabelas do lattes
--       Retorna título e pesquisador das produções que contenham "dengue" E "fever"
SELECT
    busca.producoes_id,
    busca.titulo_artigo,
    busca.nome_pesquisador
FROM (
    SELECT
        p.producoes_id,
        p.titulo_artigo,
        r.nome_pesquisador,
        to_tsvector('simple', p.titulo_artigo)   ||
        to_tsvector('simple', r.nome_pesquisador) AS documento
    FROM producoes p
    JOIN pesquisadores r ON r.pesquisadores_id = p.pesquisadores_id
) busca
WHERE busca.documento @@ to_tsquery('simple', 'dengue & fever');
-- Retorna 3 artigos sobre dengue e febre de Hugo Saba:
-- "Self-affinity in the dengue fever time series";
-- "Self-affinity and self-organized criticality applied to the relationship between the economic arrangements and the dengue fever spread in Bahia";
-- "Paradox between adequate sanitation and rainfall in dengue fever cases";


-- =============================================================================
-- SEÇÃO 3 – SUPORTE A IDIOMAS
-- Tutorial: "Language Support"
-- =============================================================================

-- 3.1 – O mesmo título tratado com configurações de idioma diferentes
--       'english' aplica stemming inglês: "cities" → "citi", "spread" → "spread"
--       'portuguese' aplica stemming português — não reconhece palavras em inglês
--       'simple' mantém todos os tokens sem stemming (recomendado para corpus misto)
SELECT to_tsvector('english', 'Synchronized spread of COVID-19 in the cities of Bahia, Brazil');
-- '-19':5 'bahia':10 'brazil':11 'citi':8 'covid':4 'spread':2 'synchron':1

SELECT to_tsvector('portuguese', 'Synchronized spread of COVID-19 in the cities of Bahia, Brazil');
-- "'-19':5 'bah':10 'brazil':11 'citi':8 'covid':4 'in':6 'of':3,9 'spread':2 'synchronized':1 'the':7"

SELECT to_tsvector('simple', 'Synchronized spread of COVID-19 in the cities of Bahia, Brazil');
-- "'-19':5 'bahia':10 'brazil':11 'cities':8 'covid':4 'in':6 'of':3,9 'spread':2 'synchronized':1 'the':7"

-- 3.2 – Exemplo com título em português
--       'portuguese' stemiza corretamente: "redes" → "red", "complexas" → "complex"
--       'english' pode stemizar incorretamente palavras em português
--       'simple' mantém os tokens originais sem qualquer transformação
SELECT to_tsvector('portuguese', 'Redes complexas de homonimos para analise semantica textual');
-- "'analis':6 'complex':2 'homon':4 'red':1 'semant':7 'textual':8"

SELECT to_tsvector('english', 'Redes complexas de homonimos para analise semantica textual');
-- "'analis':6 'complexa':2 'de':3 'homonimo':4 'para':5 'rede':1 'semantica':7 'textual':8"

SELECT to_tsvector('simple', 'Redes complexas de homonimos para analise semantica textual');
-- "'analise':6 'complexas':2 'de':3 'homonimos':4 'para':5 'redes':1 'semantica':7 'textual':8"

-- 3.3 – Configuração 'simple' para nomes de pesquisadores
--       Nomes próprios NÃO devem ser stemizados — 'simple' é sempre o correto para nomes
SELECT to_tsvector('simple', 'Eduardo Manuel de Freitas Jorge');
SELECT to_tsvector('english', 'Eduardo Manuel de Freitas Jorge');
-- Com 'english', "jorge" será transformado em "jorg"


-- =============================================================================
-- SEÇÃO 4 – SUPORTE A CARACTERES ACENTUADOS
-- Tutorial: "Working with Accented Characters"
-- =============================================================================

-- 4.1 – Função unaccent(): remove acentos gráficos de uma string
--       Necessária porque o corpus tem títulos com acentos em português
SELECT unaccent('Difusão e utilização de informações acadêmicas: um modelo de gestão do conhecimento para subsidiar gestores universitários');
-- Retorna a string sem acentos

-- 4.2 – Problema: buscar "educacao" sem achar "educação" (e vice-versa)
--       Sem unaccent, a busca é case-sensitive em relação aos acentos
SELECT to_tsvector('simple', 'A teoria fundamentada em dados aplicada ao campo da educacao superior')
    @@ to_tsquery('simple', 'educação');
-- Retorna false (os lexemas não coincidem devido aos acentos)

-- 4.3 – Solução: aplicar unaccent tanto no documento quanto na query
SELECT to_tsvector('simple', unaccent('A teoria fundamentada em dados aplicada ao campo da educacao superior'))
    @@ to_tsquery('simple', unaccent('educação'));
-- Retorna: true  (ambos normalizados sem acento, a busca casa corretamente)

-- 4.4 – Criando uma configuração de busca personalizada para português sem acentos
--       Recomendado em vez de chamar unaccent() manualmente em cada consulta.
--       A config 'pt' aplica unaccent + stemming português automaticamente.
CREATE TEXT SEARCH CONFIGURATION pt (COPY = portuguese);
ALTER TEXT SEARCH CONFIGURATION pt
    ALTER MAPPING FOR hword, hword_part, word
    WITH unaccent, portuguese_stem;

-- 4.5 – Usando a configuração personalizada 'pt' em títulos do corpus
SELECT to_tsvector('portuguese', 'Difusao e utilizacao de informacoes academicas');
-- Sem unaccent no mapeamento: acentos na query precisam bater

SELECT to_tsvector('pt', 'Difusão e utilização de informações acadêmicas');
-- Com config 'pt': acentos removidos automaticamente pelo unaccent no mapeamento

-- 4.6 – Busca tolerante a acentos com a config personalizada
SELECT to_tsvector('pt', 'Difusão e utilização de informações acadêmicas')
    @@ to_tsquery('pt', 'informacoes') AS resultado;
-- Retorna: true  (encontra "informações" buscando por "informacoes")


-- =============================================================================
-- SEÇÃO 5 – CLASSIFICAÇÃO E RANKING (setweight + ts_rank)
-- Tutorial: "Document Classification / Ranking"
-- =============================================================================

-- 5.1 – setweight(): atribui peso 'A'a'D' às partes do documento
--       'A' = maior relevância → título do artigo (campo principal de busca)
--       'C' = menor relevância → nome do pesquisador (campo secundário)
--       Pesos afetam o score retornado por ts_rank()
SELECT
    busca.producoes_id,
    busca.titulo_artigo,
    busca.nome_pesquisador,
    ts_rank(busca.documento, to_tsquery('simple', 'dengue | fever')) AS relevancia
FROM (
    SELECT
        p.producoes_id,
        p.titulo_artigo,
        r.nome_pesquisador,
        setweight(to_tsvector('simple', p.titulo_artigo), 'A') ||
        setweight(to_tsvector('simple', r.nome_pesquisador), 'C') AS documento
    FROM producoes p
    JOIN pesquisadores r ON r.pesquisadores_id = p.pesquisadores_id
) busca
WHERE busca.documento @@ to_tsquery('simple', 'dengue | fever')
ORDER BY relevancia DESC;
-- Artigos com os termos no título (peso A) aparecem antes dos que só têm no nome do autor

-- 5.2 – Exemplos isolados de ts_rank() para entender o scoring
--       Quanto mais vezes e com maior peso o termo aparece, maior o score


SELECT ts_rank(
    to_tsvector('simple', 'Self-affinity in the dengue fever time series'),
    to_tsquery('simple', 'dengue | fever')
) AS relevancia;
-- Resultado: 0.06079271
-- OR usa o score máximo entre os termos, não a soma — igual ao de um único termo

SELECT ts_rank(
    to_tsvector('simple', 'Self-affinity in the dengue fever time series'),
    to_tsquery('simple', 'dengue')
) AS relevancia;
-- Resultado: 0.06079271
-- Mesmo score que o OR acima: ambos casam uma vez no mesmo documento curto

SELECT ts_rank(
    to_tsvector('simple', 'Self-affinity in the dengue fever time series'),
    to_tsquery('simple', 'dengue & fever')
) AS relevancia;
-- Resultado: 0.09910322
-- AND combina as posições dos dois termos → score mais alto que OR ou termo único

SELECT ts_rank(
    to_tsvector('simple', 'Self-affinity in the dengue fever time series'),
    to_tsquery('simple', 'dengue & covid')
) AS relevancia;
-- Resultado: 1e-20
-- AND com 'covid' ausente no documento → score praticamente zero


-- =============================================================================
-- SEÇÃO 6 – OTIMIZAÇÃO E INDEXAÇÃO
-- Tutorial: "Optimization and Indexing"
-- =============================================================================

-- 6.1 – Índice GIN diretamente na tabela producoes
--       GIN: ideal para dados estáticos, consultas rápidas, índice maior
--       GiST: ideal para dados dinâmicos, atualizações rápidas, pode ter falsos positivos
--       Como só temos titulo_artigo como campo textual, o índice é direto e simples
CREATE INDEX IF NOT EXISTS idx_fts_producoes
    ON producoes
    USING gin(to_tsvector('simple', titulo_artigo));

-- 6.2 – Criando uma MATERIALIZED VIEW como índice de busca
--       Necessária quando o documento combina múltiplas tabelas (JOIN).
--       O documento pré-calculado na view pode receber um índice GIN dedicado.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_indice_busca AS
SELECT
    p.producoes_id,
    p.titulo_artigo,
    p.ano_artigo,
    r.nome_pesquisador,
    setweight(to_tsvector('simple', p.titulo_artigo),    'A') ||
    setweight(to_tsvector('simple', r.nome_pesquisador), 'C') AS documento
FROM producoes p
JOIN pesquisadores r ON r.pesquisadores_id = p.pesquisadores_id;

-- 6.3 – Índice GIN sobre a coluna documento da materialized view
CREATE INDEX IF NOT EXISTS idx_fts_mv_busca
    ON mv_indice_busca
    USING gin(documento);

-- 6.4 – Consulta usando a materialized view. Simples e eficiente
SELECT producoes_id, titulo_artigo, nome_pesquisador, ano_artigo
FROM mv_indice_busca
WHERE documento @@ to_tsquery('simple', 'dengue & fever')
ORDER BY ts_rank(documento, to_tsquery('simple', 'dengue & fever')) DESC;



-- =============================================================================
-- SEÇÃO 7 – CORREÇÃO ORTOGRÁFICA (pg_trgm)
-- Tutorial: "Spelling Errors"
-- =============================================================================

-- 7.1 – similarity(): retorna float [0, 1] indicando semelhança por trigramas
--       (sequências de 3 caracteres consecutivos)
SELECT similarity('dengue',  'dengue');   -- 1.0   (idêntico)
SELECT similarity('dengue',  'dngue');    -- ~0.44  (erro de digitação)
SELECT similarity('dengue',  'COVID-19'); -- ~0     (sem relação)
SELECT similarity('education', 'eduaction'); -- ~0.43 (transposição de letras)

-- 7.2 – Criando uma materialized view com todos os lexemas únicos do corpus
--       Usamos 'simple' para não alterar os tokens — queremos sugerir as palavras
--       exatamente como aparecem nos títulos e nomes, sem stemming
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_lexemas_unicos AS
SELECT word
FROM ts_stat(
    'SELECT
         to_tsvector(''simple'', p.titulo_artigo) ||
         to_tsvector(''simple'', r.nome_pesquisador)
     FROM public.producoes p
     JOIN public.pesquisadores r ON r.pesquisadores_id = p.pesquisadores_id'
);

-- 7.3 – Índice de trigramas sobre os lexemas para buscas de similaridade rápidas
CREATE INDEX IF NOT EXISTS idx_trgm_lexemas
    ON mv_lexemas_unicos
    USING gin(word gin_trgm_ops);

-- 7.4 – Encontrando o lexema mais próximo de uma palavra com erro de digitação
--       O operador <-> (distância) retorna valores menores para strings mais similares.
--       Limiar 0.3 é ponto de partida; 0.5 terá mais precisão.
SELECT word, similarity(word, 'dngue') AS score
FROM mv_lexemas_unicos
WHERE similarity(word, 'dngue') > 0.3
ORDER BY word <-> 'dngue'
LIMIT 5;
-- Retorna: "dengue" | Precisão: 0.44445

SELECT word, similarity(word, 'eduaction') AS score
FROM mv_lexemas_unicos
WHERE similarity(word, 'eduaction') > 0.3
ORDER BY word <-> 'eduaction'
LIMIT 5;
-- Retorna: "education" | Precisão: 0.42875

-- 7.5 – Fluxo completo de busca tolerante a erros ortográficos:
--       1. Recebe termo com possível erro ('dngue')
--       2. Busca o lexema mais similar no corpus da view mv_lexemas_unicos
--       3. Usa o lexema corrigido na consulta FTS final sobre mv_indice_busca
WITH termo_corrigido AS (
    SELECT word AS termo
    FROM mv_lexemas_unicos
    WHERE similarity(word, 'dngue') > 0.3
    ORDER BY word <-> 'dngue'
    LIMIT 1
)
SELECT
    mv.producoes_id,
    mv.titulo_artigo,
    mv.nome_pesquisador,
    mv.ano_artigo,
    ts_rank(mv.documento, to_tsquery('simple', tc.termo)) AS relevancia
FROM mv_indice_busca mv, termo_corrigido tc
WHERE mv.documento @@ to_tsquery('simple', tc.termo)
ORDER BY relevancia DESC;
-- Mesmo digitando 'dngue', retorna artigos sobre dengue corretamente. Relevância de ~0.6
