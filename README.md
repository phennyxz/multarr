# multarr

Estruturas de dados multidimensionais **tipadas** em **Bash puro**: objetos e listas aninhados, tipos (string, int, float, bool, null), conversão de/para JSON, iteradores e modificadores — sem `jq`, `python` ou qualquer processo externo para ler os dados.

Basta dar `source` em um único arquivo:

```bash
source multarr.sh
json_to_multarr '{"servidor": {"host": "localhost", "porta": 8080}, "tags": ["dev", "bash"]}'
multarr_get 'root{servidor}{host}'   # localhost
multarr_get 'root{tags}[0]'          # dev
```

## Sumário

- [Por que usar](#por-que-usar)
- [Requisitos e instalação](#requisitos-e-instalação)
- [Visão geral das quatro abordagens](#visão-geral-das-quatro-abordagens)
- [multarr (core)](#multarr-core)
- [planarr](#planarr)
- [strucarr](#strucarr)
- [typarr](#typarr)
- [Qual escolher?](#qual-escolher)
- [Segurança](#segurança)
- [Limitações](#limitações)
- [Testes](#testes)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Licença](#licença)

## Por que usar

O Bash não tem objetos nem arrays multidimensionais. As alternativas usuais têm custos:

| Abordagem | Problema |
|---|---|
| Achatar tudo em variáveis | Perde tipos e a estrutura de listas |
| `jq` / `python` | Dependência externa e um processo por consulta |
| `eval` / serialização | Risco de segurança e baixa legibilidade |

O multarr guarda tudo em arrays associativos nativos do Bash, com uma notação de caminho explícita e tipos detectados automaticamente.

## Requisitos e instalação

- **Bash 4.3 ou superior** (usa `declare -g`, arrays associativos e `local -n`). No macOS, instale um Bash mais novo (`brew install bash`).
- Nenhuma outra dependência; apenas `sort` (coreutils) é usado na serialização.

```bash
git clone https://github.com/phennyxz/multarr.git
source multarr/multarr.sh
```

## Visão geral das quatro abordagens

Todas partem de um JSON e oferecem formatos de chave diferentes para o mesmo dado `{"admin":{"papeis":["x"]}}`:

| Módulo | Chave de `admin.papeis[0]` | Guarda tipos | Distingue `{}` de `[]` | Reconstrói JSON |
|---|---|---|---|---|
| `multarr` | `root{admin}{papeis}[0]` | sim (array separado) | sim | sim |
| `planarr` | `admin/papeis/0` | não | não | não |
| `strucarr` | `root{admin}{papeis}[0]` | sim (`<nome>_types`) | sim | sim |
| `typarr` | `ols:admin/papeis/0` | sim (no prefixo da chave) | sim | sim |

## multarr (core)

Os dados ficam nos arrays globais `MULTARR_DATA` (valores) e `MULTARR_TYPES` (tipos). Notação: `{chave}` para objeto, `[indice]` para lista, a partir de uma raiz (por padrão `root`).

```bash
json_to_multarr '{"servidor": {"host": "localhost", "porta": 8080}, "tags": ["dev", "bash"]}'
```

Gera:

```
root{servidor}{host} = localhost (string)
root{servidor}{porta} = 8080 (int)
root{tags}[0] = dev (string)
root{tags}[1] = bash (string)
```

**Tipos detectados:** `string`, `int`, `float`, `bool` (`true`/`false`), `null`. Strings entre aspas no JSON são sempre `string` (`"123"` continua string).

### Funções

| Função | Descrição |
|---|---|
| `multarr_set <caminho> <valor> [tipo]` | Define um valor; o tipo é detectado se omitido (`auto`) |
| `multarr_get <caminho> [padrão]` | Imprime o valor, ou o padrão se não existir |
| `multarr_type <caminho>` | Imprime o tipo (vazio se não existir) |
| `multarr_exists <caminho>` | Código de saída 0 se existir |
| `json_to_multarr <json> [raiz]` | Carrega JSON sob a raiz informada |
| `multarr_to_json [raiz]` | Serializa de volta para JSON (compacto, chaves ordenadas) |
| `multarr_foritem <pai> <comando>` | Executa o comando para cada filho direto de `<pai>` (`$MA_KEY`, `$MA_VAL`) |
| `multarr_fortype <tipo> <comando> [base]` | Executa para cada valor do tipo (`$MA_PATH`, `$MA_VAL`) |
| `multarr_forpath <padrão> <comando>` | Executa para cada caminho que casa com o glob (`$MA_PATH`, `$MA_VAL`) |
| `multarr_mod_upper <padrão>` | Converte para maiúsculas os valores `string` que casam |
| `multarr_mod_incr <padrão> [n]` | Soma `n` (padrão 1) aos valores `int` que casam |
| `multarr_mod_delete <padrão>` | Remove as entradas que casam |

### Exemplos

```bash
multarr_foritem 'root{tags}' 'echo "Tag: $MA_VAL"'
multarr_fortype int 'echo "Inteiro em $MA_PATH: $MA_VAL"'
multarr_forpath 'root{servidor}*' 'echo "$MA_PATH"'

multarr_mod_upper 'root{tags}*'
multarr_mod_incr 'root{servidor}{porta}'
multarr_mod_delete 'root{servidor}{host}'

multarr_to_json
# {"servidor":{"porta":8081},"tags":["DEV","BASH"]}
```

Valores também podem ser definidos manualmente, e a estrutura é só um conjunto de caminhos:

```bash
multarr_set 'root{jogador}{vidas}' 3
multarr_set 'root{jogador}{nome}' 'Ana'
multarr_set 'root{jogador}{vivo}' true
```

> Padrões de `forpath`/`mod_*` são globs do Bash: `[` e `]` têm significado especial. Para casar índices de lista, use `*` (ex.: `root{tags}*`) ou escape os colchetes.

## planarr

Achata o JSON em um array associativo **seu**, com caminhos separados por `/`. Só valores, sem tipos. É a opção mais simples e leve.

```bash
declare -A m
planarr m '{"portas":[80,443],"admin":{"nome":"Carlos","papeis":["admin","dev"]}}'
echo "${m[portas/1]}"          # 443
echo "${m[admin/papeis/0]}"    # admin
```

Strings aceitam os escapes `\n`, `\t`, `\r`, `\"`, `\\`. Sequências `\uXXXX` não são decodificadas.

## strucarr

Mesma notação e mesmo motor do multarr, mas em um **array com o nome que você escolher**, acessível diretamente por expansão do Bash. Valores em `<nome>`, tipos em `<nome>_types`.

```bash
strucarr_parse data '{"servidor":{"host":"localhost","porta":8080},"usuarios":[{"nome":"Carlos"},{"nome":"Ana"}]}'

echo "${data['root{usuarios}[1]{nome}']}"      # Ana
strucarr_get data 'root{servidor}{host}'        # localhost
strucarr_type data 'root{servidor}{porta}'      # int
strucarr_to_json data
```

Funções: `strucarr_parse <nome> <json> [raiz]`, `strucarr_set <nome> <caminho> <valor> [tipo]`, `strucarr_get <nome> <caminho> [padrão]`, `strucarr_type <nome> <caminho>` (retorna `unknown` se não existir) e `strucarr_to_json <nome> [raiz]`.

## typarr

Chaves **autodescritivas**: o prefixo antes de `:` tem **uma letra por nível do caminho** com o tipo daquele nó.

| Letra | Tipo |
|---|---|
| `o` | objeto |
| `l` | lista |
| `s` `i` `f` `b` `n` | string, int, float, bool, null (folhas) |

```bash
typarr_parse m '{"admin":{"nome":"Carlos","papeis":["admin","dev"],"nivel":3},"score":-42.5}'

echo "${m['ols:admin/papeis/1']}"   # dev    (admin=objeto, papeis=lista, 1=string)
echo "${m['oi:admin/nivel']}"       # 3      (admin=objeto, nivel=int)
echo "${m[':']}"                    # o      (tipo da raiz)

typarr_get m admin/papeis/0         # admin  (sem precisar do prefixo)
typarr_type m score                 # float
typarr_fortype m i 'echo "$MA_PATH = $MA_VAL"'   # todos os inteiros
typarr_to_json m
```

O array auxiliar `<nome>_idx` mapeia o caminho simples para a chave completa e é usado por `typarr_get`/`typarr_type`.

## Qual escolher?

| Cenário | Recomendação |
|---|---|
| Ler alguns valores de uma configuração, com mínimo overhead | `planarr` |
| Dados aninhados com listas e objetos, acesso por caminho, iteradores e modificadores | `multarr` |
| Mesmo que o anterior, mas com vários conjuntos de dados coexistindo | `strucarr` |
| Validar tipos, filtrar por tipo ou reconstruir o JSON com fidelidade | `typarr` |

## Segurança

- `multarr_foritem`, `multarr_fortype`, `multarr_forpath`, `typarr_fortype` executam o comando com **`eval`**. Passe apenas comandos escritos por você, nunca texto vindo de dados externos.
- Os dados carregados do JSON nunca são avaliados como código; só o argumento `<comando>` dos iteradores é.
- O parser é tolerante, **não é um validador de JSON**: entradas malformadas podem produzir resultados parciais.

## Limitações

- O parser percorre o texto caractere a caractere em Bash; para JSON grande (centenas de KB) será lento. Para esse caso, prefira uma ferramenta nativa.
- Objetos e listas **vazios** não são representados e portanto não aparecem na reconstrução do JSON.
- A serialização é compacta, com chaves de objeto em ordem alfabética (não a ordem original).
- `typarr` e `planarr`: chaves de objeto não podem conter `/`. Em `multarr`/`strucarr`, não podem conter `}`.
- Escapes `\uXXXX` não são decodificados.
- `multarr`, `planarr`, `strucarr` e `typarr` compartilham funções auxiliares internas com prefixo `_ma_`, `_pa_`, `_ta_`; evite nomes iguais.

## Testes

```bash
bash test.sh
```

O script carrega a biblioteca e verifica o parser, os acessos, os iteradores, os modificadores, a serialização e o `planarr`, `strucarr` e `typarr`. Sai com código diferente de zero se alguma verificação falhar.

## Estrutura do repositório

```
multarr.sh   # biblioteca completa (core, planarr, strucarr, typarr)
test.sh      # testes e exemplos executáveis
README.md
LICENSE      # MIT
```

## Licença

[MIT](LICENSE)
