source "$(dirname "$0")/multarr.sh"
json_to_multarr '{"servidor": {"host": "localhost", "porta": 8080}, "tags": ["dev", "bash"], "ok": true, "n": [{"a":1.5},{"a":null}]}'
multarr_get 'root{servidor}{host}'; multarr_get 'root{tags}[1]'; multarr_type 'root{servidor}{porta}'
multarr_foritem 'root{tags}' 'echo "Tag: $MA_VAL"'
multarr_fortype int 'echo "int $MA_PATH=$MA_VAL"'
multarr_mod_upper 'root{tags}*'; multarr_mod_incr 'root{servidor}{porta}'
multarr_to_json; echo
multarr_mod_delete 'root{ok}'; multarr_to_json; echo
