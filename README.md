# multarr

Estruturas de dados multidimensionais tipadas em Bash puro (4.3+), com notação `root{objeto}{chave}` e `root{lista}[0]`.

- **Core:** `multarr_set`, `multarr_get`, `multarr_type`, `multarr_exists` (tipos: string, int, float, bool, null)
- **JSON:** `json_to_multarr`, `multarr_to_json`
- **Flat:** `planarr nome_do_array "$json"` achata o JSON em um array associativo (`admin/papeis/0`)
- **Strucarr:** `strucarr_parse|set|get|type|to_json <nome> ...` usa um array nomeado pelo usuário: `strucarr_parse data "$json"; echo "${data['root{usuarios}[0]{nome}']}"` (tipos em `data_types`)
- **Iteradores:** `multarr_foritem`, `multarr_fortype`, `multarr_forpath` (o comando é executado via `eval`; use apenas comandos confiáveis)
- **Modificadores:** `multarr_mod_upper`, `multarr_mod_incr`, `multarr_mod_delete`

## Uso
```bash
source multarr.sh
json_to_multarr '{"servidor": {"host": "localhost", "porta": 8080}, "tags": ["dev", "bash"]}'
multarr_get 'root{servidor}{host}'   # localhost
multarr_get 'root{tags}[0]'          # dev
multarr_foritem 'root{tags}' 'echo "Tag: $MA_VAL"'
multarr_fortype int 'echo "$MA_PATH = $MA_VAL"'
multarr_to_json
```

Teste: `bash test.sh`

## Licença
MIT
