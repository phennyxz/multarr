source "$(dirname "$0")/multarr.sh"
json_to_multarr '{"servidor": {"host": "localhost", "porta": 8080}, "tags": ["dev", "bash"], "ok": true, "n": [{"a":1.5},{"a":null}]}'
multarr_get 'root{servidor}{host}'; multarr_get 'root{tags}[1]'; multarr_type 'root{servidor}{porta}'
multarr_foritem 'root{tags}' 'echo "Tag: $MA_VAL"'
multarr_fortype int 'echo "int $MA_PATH=$MA_VAL"'
multarr_mod_upper 'root{tags}*'; multarr_mod_incr 'root{servidor}{porta}'
multarr_to_json; echo
multarr_mod_delete 'root{ok}'; multarr_to_json; echo

declare -A flat
planarr flat '{"portas":[80,443],"admin":{"nome":"Carlos","papeis":["admin","dev"]}}'
[[ "${flat[portas/1]}" == 443 && "${flat[admin/papeis/1]}" == dev ]] && echo "planarr ok" || { echo "planarr FAIL"; exit 1; }

strucarr_parse data '{"servidor":{"host":"localhost","porta":8080,"ativo":true},"usuarios":[{"nome":"Carlos","idade":30},{"nome":"Ana","idade":25}]}'
[[ "${data['root{usuarios}[1]{nome}']}" == Ana && "$(strucarr_type data 'root{servidor}{porta}')" == int ]] || { echo "strucarr FAIL"; exit 1; }
[[ "$(strucarr_to_json data)" == '{"servidor":{"ativo":true,"host":"localhost","porta":8080},"usuarios":[{"idade":30,"nome":"Carlos"},{"idade":25,"nome":"Ana"}]}' ]] || { echo "strucarr json FAIL"; exit 1; }
[[ ${#MULTARR_DATA[@]} -gt 0 ]] && echo "strucarr ok"

typarr_parse tm '{"admin":{"nome":"Carlos","papeis":["admin","dev"],"nivel":3},"ativo":true,"score":-42.5,"vazio":null,"lista":[[1,2],[3]]}'
[[ "${tm['ols:admin/papeis/1']}" == dev && "${tm['oi:admin/nivel']}" == 3 ]] || { echo "typarr key FAIL"; exit 1; }
[[ "$(typarr_get tm admin/papeis/0)" == admin && "$(typarr_type tm score)" == float && "$(typarr_type tm admin/papeis/0)" == string ]] || { echo "typarr get FAIL"; exit 1; }
[[ "$(typarr_fortype tm i 'echo $MA_PATH' | sort | tr '\n' ' ')" == "admin/nivel lista/0/0 lista/0/1 lista/1/0 " ]] || { echo "typarr fortype FAIL"; exit 1; }
typarr_to_json tm
