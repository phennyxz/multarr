#!/usr/bin/env bash
# MULTARR - Multi-dimensional Typed Array Library for Bash (v1.0.0, MIT)
# Paths: root{obj}{key}  root{list}[0]

declare -gA MULTARR_DATA=()
declare -gA MULTARR_TYPES=()

# --- CORE ---

multarr_set() {
    local path="$1" value="$2" type="${3:-auto}"
    if [[ "$type" == auto ]]; then
        if [[ "$value" == true || "$value" == false ]]; then type=bool
        elif [[ "$value" == null ]]; then type=null
        elif [[ "$value" =~ ^-?[0-9]+$ ]]; then type=int
        elif [[ "$value" =~ ^-?[0-9]+\.[0-9]+([eE][-+]?[0-9]+)?$ ]]; then type=float
        else type=string; fi
    fi
    MULTARR_DATA["$path"]="$value"
    MULTARR_TYPES["$path"]="$type"
}

multarr_get() {
    local path="$1" default="${2:-}"
    if [[ -n "${MULTARR_TYPES[$path]+x}" ]]; then printf '%s\n' "${MULTARR_DATA[$path]}"
    else printf '%s\n' "$default"; fi
}

multarr_type() { printf '%s\n' "${MULTARR_TYPES[$1]:-}"; }

multarr_exists() { [[ -n "${MULTARR_TYPES[$1]+x}" ]]; }

# --- PARSER (JSON -> Multarr) ---

_ma_ws() { while [[ "${_MA_J:_MA_I:1}" == [[:space:]] ]]; do ((_MA_I++)); done; }

# Reads a JSON string at _MA_I into _MA_STR
_ma_str() {
    local c out=""
    ((_MA_I++)) # opening quote
    while ((_MA_I < ${#_MA_J})); do
        c="${_MA_J:_MA_I:1}"
        if [[ "$c" == '\' ]]; then
            ((_MA_I++)); c="${_MA_J:_MA_I:1}"
            case "$c" in n) c=$'\n' ;; t) c=$'\t' ;; r) c=$'\r' ;; esac
            out+="$c"
        elif [[ "$c" == '"' ]]; then ((_MA_I++)); break
        else out+="$c"; fi
        ((_MA_I++))
    done
    _MA_STR="$out"
}

_ma_value() {
    local path="$1" c key idx=0 lit
    _ma_ws
    c="${_MA_J:_MA_I:1}"
    case "$c" in
        '{')
            ((_MA_I++)); _ma_ws
            if [[ "${_MA_J:_MA_I:1}" == '}' ]]; then ((_MA_I++)); return; fi
            while ((_MA_I < ${#_MA_J})); do
                _ma_ws; _ma_str; key="$_MA_STR"
                _ma_ws; ((_MA_I++)) # ':'
                _ma_value "${path}{${key}}"
                _ma_ws
                c="${_MA_J:_MA_I:1}"; ((_MA_I++))
                [[ "$c" == ',' ]] || break
            done ;;
        '[')
            ((_MA_I++)); _ma_ws
            if [[ "${_MA_J:_MA_I:1}" == ']' ]]; then ((_MA_I++)); return; fi
            while ((_MA_I < ${#_MA_J})); do
                _ma_value "${path}[${idx}]"; ((idx++))
                _ma_ws
                c="${_MA_J:_MA_I:1}"; ((_MA_I++))
                [[ "$c" == ',' ]] || break
            done ;;
        '"') _ma_str; multarr_set "$path" "$_MA_STR" string ;;
        *)
            lit=""
            while ((_MA_I < ${#_MA_J})); do
                c="${_MA_J:_MA_I:1}"
                [[ "$c" == [,\}\][:space:]] ]] && break
                lit+="$c"; ((_MA_I++))
            done
            multarr_set "$path" "$lit" ;;
    esac
}

json_to_multarr() {
    local _MA_J="$1" _MA_I=0 _MA_STR=""
    _ma_value "${2:-root}"
}

# --- SERIALIZER (Multarr -> JSON) ---

_ma_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

multarr_to_json() {
    local base="${1:-root}" key rem tok kind
    local -A seen=()
    local -a toks=()
    if [[ -n "${MULTARR_TYPES[$base]+x}" ]]; then
        local v="${MULTARR_DATA[$base]}"
        case "${MULTARR_TYPES[$base]}" in
            string) printf '"%s"' "$(_ma_json_escape "$v")" ;;
            *) printf '%s' "$v" ;;
        esac
        return
    fi
    for key in "${!MULTARR_DATA[@]}"; do
        [[ "$key" == "$base"[\{\[]* ]] || continue
        rem="${key#"$base"}"
        if [[ "$rem" == \{* ]]; then tok="${rem%%\}*}}"; kind=obj
        else tok="${rem%%\]*}]"; kind=arr; fi
        if [[ -z "${seen[$tok]+x}" ]]; then seen["$tok"]="$kind"; toks+=("$tok"); fi
    done
    ((${#toks[@]})) || { printf 'null'; return; }
    local sep="" name
    if [[ "${seen[${toks[0]}]}" == arr ]]; then
        printf '['
        while IFS= read -r tok; do
            printf '%s' "$sep"; multarr_to_json "${base}${tok}"; sep=","
        done < <(printf '%s\n' "${toks[@]}" | sort -t'[' -k2 -n)
        printf ']'
    else
        printf '{'
        while IFS= read -r tok; do
            name="${tok:1:${#tok}-2}"
            printf '%s"%s":' "$sep" "$(_ma_json_escape "$name")"
            multarr_to_json "${base}${tok}"; sep=","
        done < <(printf '%s\n' "${toks[@]}" | sort)
        printf '}'
    fi
}

# --- ITERATORS (command runs via eval: only pass trusted commands) ---

multarr_foritem() {
    local parent="$1" command="$2" key rem tok MA_KEY MA_VAL
    local -A seen=()
    for key in "${!MULTARR_DATA[@]}"; do
        [[ "$key" == "$parent"[\{\[]* ]] || continue
        rem="${key#"$parent"}"
        if [[ "$rem" == \{* ]]; then tok="${rem%%\}*}}"; else tok="${rem%%\]*}]"; fi
        [[ -n "${seen[$tok]+x}" ]] && continue
        seen["$tok"]=1
        MA_KEY="$tok"
        MA_VAL="${MULTARR_DATA[${parent}${tok}]-}"
        eval "$command"
    done
}

multarr_fortype() {
    local want="$1" command="$2" base="${3:-}" key MA_PATH MA_VAL
    for key in "${!MULTARR_TYPES[@]}"; do
        [[ "${MULTARR_TYPES[$key]}" == "$want" ]] || continue
        [[ -z "$base" || "$key" == "$base"* ]] || continue
        MA_PATH="$key"; MA_VAL="${MULTARR_DATA[$key]}"
        eval "$command"
    done
}

multarr_forpath() {
    local pattern="$1" command="$2" key MA_PATH MA_VAL
    for key in "${!MULTARR_DATA[@]}"; do
        [[ "$key" == $pattern ]] || continue
        MA_PATH="$key"; MA_VAL="${MULTARR_DATA[$key]}"
        eval "$command"
    done
}

# --- MODIFIERS ---

multarr_mod_upper() {
    local pattern="$1" key
    for key in "${!MULTARR_DATA[@]}"; do
        [[ "$key" == $pattern && "${MULTARR_TYPES[$key]}" == string ]] &&
            MULTARR_DATA["$key"]="${MULTARR_DATA[$key]^^}"
    done
    return 0
}

multarr_mod_incr() {
    local pattern="$1" by="${2:-1}" key
    for key in "${!MULTARR_DATA[@]}"; do
        [[ "$key" == $pattern && "${MULTARR_TYPES[$key]}" == int ]] &&
            MULTARR_DATA["$key"]=$(( ${MULTARR_DATA[$key]} + by ))
    done
    return 0
}

multarr_mod_delete() {
    local pattern="$1" key
    for key in "${!MULTARR_DATA[@]}"; do
        if [[ "$key" == $pattern ]]; then
            unset "MULTARR_DATA[$key]" "MULTARR_TYPES[$key]"
        fi
    done
    return 0
}

# --- PLANARR (JSON -> flat associative array, paths like admin/papeis/0) ---
# Usage: declare -A map; planarr map "$json"

_pa_value() {
    local path="$1" c key idx=0 lit sub
    _ma_ws
    c="${_MA_J:_MA_I:1}"
    case "$c" in
        '{')
            ((_MA_I++)); _ma_ws
            if [[ "${_MA_J:_MA_I:1}" == '}' ]]; then ((_MA_I++)); return; fi
            while ((_MA_I < ${#_MA_J})); do
                _ma_ws; _ma_str; key="$_MA_STR"
                _ma_ws; ((_MA_I++))
                _pa_value "${path:+$path/}${key}"
                _ma_ws
                c="${_MA_J:_MA_I:1}"; ((_MA_I++))
                [[ "$c" == ',' ]] || break
            done ;;
        '[')
            ((_MA_I++)); _ma_ws
            if [[ "${_MA_J:_MA_I:1}" == ']' ]]; then ((_MA_I++)); return; fi
            while ((_MA_I < ${#_MA_J})); do
                _pa_value "${path:+$path/}${idx}"; ((idx++))
                _ma_ws
                c="${_MA_J:_MA_I:1}"; ((_MA_I++))
                [[ "$c" == ',' ]] || break
            done ;;
        '"') _ma_str; _PA_ARR["$path"]="$_MA_STR" ;;
        *)
            lit=""
            while ((_MA_I < ${#_MA_J})); do
                c="${_MA_J:_MA_I:1}"
                [[ "$c" == [,\}\][:space:]] ]] && break
                lit+="$c"; ((_MA_I++))
            done
            _PA_ARR["$path"]="$lit" ;;
    esac
}

planarr() {
    local -n _PA_ARR="$1"
    local _MA_J="$2" _MA_I=0 _MA_STR=""
    _pa_value ""
}

# --- STRUCARR (user-named arrays: ${data['root{a}[0]{b}']}) ---
# Data lives in <name>, types in <name>_types. Reuses the multarr engine by
# rebinding MULTARR_DATA/MULTARR_TYPES to them (bash dynamic scoping).
# Types are the multarr ones: string, int, float, bool, null.

strucarr_parse() {
    local _sa="$1"
    declare -gA "$_sa" "${_sa}_types"
    local -n MULTARR_DATA="$_sa" MULTARR_TYPES="${_sa}_types"
    json_to_multarr "$2" "${3:-root}"
}

strucarr_set() {
    local _sa="$1"
    declare -gA "$_sa" "${_sa}_types"
    local -n MULTARR_DATA="$_sa" MULTARR_TYPES="${_sa}_types"
    multarr_set "$2" "$3" "${4:-auto}"
}

strucarr_get() {
    local -n MULTARR_DATA="$1" MULTARR_TYPES="${1}_types"
    multarr_get "$2" "${3:-}"
}

strucarr_type() {
    local -n MULTARR_DATA="$1" MULTARR_TYPES="${1}_types"
    local t; t="$(multarr_type "$2")"
    printf '%s\n' "${t:-unknown}"
}

strucarr_to_json() {
    local -n MULTARR_DATA="$1" MULTARR_TYPES="${1}_types"
    multarr_to_json "${2:-root}"
}

# --- TYPARR (typed flat keys: ${map['ols:admin/papeis/0']}) ---
# Key = "<letters>:<path>"; one letter per path segment gives that node's type:
#   o=object  l=list  s=string  i=int  f=float  b=bool  n=null
# e.g. {"admin":{"papeis":["x"]}} -> map['ols:admin/papeis/0']=x
# map[':'] holds the root kind (o or l). <name>_idx maps plain path -> full key.
# Object keys must not contain '/'.

_ta_type_word() {
    case "$1" in
        o) echo object ;; l) echo list ;; s) echo string ;; i) echo int ;;
        f) echo float ;; b) echo bool ;; n) echo null ;; *) echo unknown ;;
    esac
}

_ta_value() {
    local path="$1" pfx="$2" c key idx=0 lit t
    _ma_ws
    c="${_MA_J:_MA_I:1}"
    case "$c" in
        '{')
            _TA[':']="${_TA[':']:-o}"
            [[ -n "$path" ]] && pfx+=o
            ((_MA_I++)); _ma_ws
            if [[ "${_MA_J:_MA_I:1}" == '}' ]]; then ((_MA_I++)); return; fi
            while ((_MA_I < ${#_MA_J})); do
                _ma_ws; _ma_str; key="$_MA_STR"
                _ma_ws; ((_MA_I++))
                _ta_value "${path:+$path/}${key}" "${pfx}"
                _ma_ws
                c="${_MA_J:_MA_I:1}"; ((_MA_I++))
                [[ "$c" == ',' ]] || break
            done ;;
        '[')
            _TA[':']="${_TA[':']:-l}"
            [[ -n "$path" ]] && pfx+=l
            ((_MA_I++)); _ma_ws
            if [[ "${_MA_J:_MA_I:1}" == ']' ]]; then ((_MA_I++)); return; fi
            while ((_MA_I < ${#_MA_J})); do
                _ta_value "${path:+$path/}${idx}" "${pfx}"; ((idx++))
                _ma_ws
                c="${_MA_J:_MA_I:1}"; ((_MA_I++))
                [[ "$c" == ',' ]] || break
            done ;;
        *)
            if [[ "$c" == '"' ]]; then _ma_str; lit="$_MA_STR"; t=s
            else
                lit=""
                while ((_MA_I < ${#_MA_J})); do
                    c="${_MA_J:_MA_I:1}"
                    [[ "$c" == [,\}\][:space:]] ]] && break
                    lit+="$c"; ((_MA_I++))
                done
                if [[ "$lit" == true || "$lit" == false ]]; then t=b
                elif [[ "$lit" == null ]]; then t=n
                elif [[ "$lit" =~ ^-?[0-9]+$ ]]; then t=i
                elif [[ "$lit" =~ ^-?[0-9]+\.[0-9]+([eE][-+]?[0-9]+)?$ ]]; then t=f
                else t=s; fi
            fi
            _TA["${pfx}${t}:${path}"]="$lit"
            _TA_IDX["$path"]="${pfx}${t}:${path}" ;;
    esac
}

typarr_parse() {
    local _ta="$1"
    declare -gA "$_ta" "${_ta}_idx"
    local -n _TA="$_ta" _TA_IDX="${_ta}_idx"
    _TA=(); _TA_IDX=()
    local _MA_J="$2" _MA_I=0 _MA_STR=""
    _ta_value "" ""
}

typarr_get() {
    local -n _TA="$1" _TA_IDX="${1}_idx"
    if [[ -n "${_TA_IDX[$2]+x}" ]]; then printf '%s\n' "${_TA[${_TA_IDX[$2]}]}"
    else printf '%s\n' "${3:-}"; fi
}

typarr_type() {
    local -n _TA_IDX="${1}_idx"
    local k="${_TA_IDX[$2]:-}"
    local l="${k%%:*}"
    _ta_type_word "${l: -1}"
}

# Runs <command> (eval) for every leaf of the given type letter (i, s, f, b, n).
# Exposes MA_PATH (plain path) and MA_VAL.
typarr_fortype() {
    local -n _TA="$1"
    local want="$2" command="$3" key letters MA_PATH MA_VAL
    for key in "${!_TA[@]}"; do
        [[ "$key" == ':' ]] && continue
        letters="${key%%:*}"
        [[ "${letters: -1}" == "$want" ]] || continue
        MA_PATH="${key#*:}"; MA_VAL="${_TA[$key]}"
        eval "$command"
    done
}

_ta_json() {
    local base="$1" d="$2" kind="$3" key letters path name tok
    local -a parts
    local -A seen=() ckind=()
    local -a names=()
    for key in "${!_TA[@]}"; do
        [[ "$key" == ':' ]] && continue
        letters="${key%%:*}"; path="${key#*:}"
        IFS='/' read -ra parts <<< "$path"
        ((${#parts[@]} > d)) || continue
        local pre=""
        for ((tok = 0; tok < d; tok++)); do pre+="${pre:+/}${parts[tok]}"; done
        [[ "$pre" == "$base" ]] || continue
        name="${parts[d]}"
        if [[ -z "${seen[$name]+x}" ]]; then
            seen["$name"]=1; names+=("$name"); ckind["$name"]="${letters:d:1}"
        fi
    done
    local sep=""
    if [[ "$kind" == l ]]; then
        printf '['
        while IFS= read -r name; do
            printf '%s' "$sep"; _ta_child "$name"; sep=","
        done < <(printf '%s\n' "${names[@]}" | sort -n)
        printf ']'
    else
        printf '{'
        while IFS= read -r name; do
            printf '%s"%s":' "$sep" "$(_ma_json_escape "$name")"; _ta_child "$name"; sep=","
        done < <(printf '%s\n' "${names[@]}" | sort)
        printf '}'
    fi
}

_ta_child() {
    local name="$1" k="${ckind[$name]}" cp="${base:+$base/}$name"
    if [[ "$k" == o || "$k" == l ]]; then
        _ta_json "$cp" "$((d + 1))" "$k"
    else
        local key="${_TA_IDX[$cp]}" v="${_TA[${_TA_IDX[$cp]}]}"
        case "$k" in
            s) printf '"%s"' "$(_ma_json_escape "$v")" ;;
            *) printf '%s' "$v" ;;
        esac
    fi
}

typarr_to_json() {
    local -n _TA="$1" _TA_IDX="${1}_idx"
    [[ -n "${_TA[:]+x}" ]] || { printf 'null\n'; return; }
    _ta_json "" 0 "${_TA[:]}"; echo
}
