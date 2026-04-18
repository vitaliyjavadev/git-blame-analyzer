#!/bin/bash
set -uo pipefail

# =============================================================================
# Git Blame Analyzer v1.0
# =============================================================================
# Author:     VitaliyJavaDev
# License:    MIT
# Description: Инструмент для анализа распределения авторства строк кода
# =============================================================================

REPO_PATH="${1:-.}"
cd "$REPO_PATH" || { echo "Ошибка: директория $REPO_PATH не найдена" >&2; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Ошибка: $REPO_PATH не является git-репозиторием" >&2; exit 1; }

#mapfile -t FILES < <(git ls-files --cached --others --exclude-standard | grep -E '\.(kt|kts|java|js|ts|py|go|rs|cpp|h|html?|css|ya?ml|json|xml|properties)$' || true)
mapfile -t FILES < <(git ls-files --cached --others --exclude-standard | grep -E '\.(kt|sql|ya?mlf|xml|properties)$' || true)

[ ${#FILES[@]} -eq 0 ] && { echo "Файлы с поддерживаемыми расширениями не найдены" >&2; exit 0; }

echo "Анализирую ${#FILES[@]} файлов..."
echo "Получаю авторство строк (git blame)..."

TEMP_DIR=$(mktemp -d) || { echo "Ошибка создания временной директории" >&2; exit 1; }

# Логирование для отладки
DEBUG_LOG="$TEMP_DIR/debug.log"
echo "=== Лог отладки ===" > "$DEBUG_LOG"
echo "Путь к репозиторию: $REPO_PATH" >> "$DEBUG_LOG"
echo "Найдено файлов: ${#FILES[@]}" >> "$DEBUG_LOG"

declare -A authors_total=()
TOTAL_LINES=0

idx=0
for file in "${FILES[@]}"; do
    ((idx++)) || true
    echo "Обработка $idx/${#FILES[@]}: $file"
    
    file_lines=$(wc -l < "$file") || { echo "Предупреждение: не удалось посчитать строки в $file" >&2; continue; }
    ((TOTAL_LINES += file_lines)) || true
    
    # Используем git blame --line-porcelain для получения информации о каждой строке
    # Каждая строка файла имеет свой хеш коммита, но один автор может иметь несколько коммитов
    # Нам нужно подсчитать количество строк для каждого автора
    
    if ! git blame --line-porcelain "$file" 2>/dev/null | grep '^author ' | sed 's/^author //g' > "$TEMP_DIR/file_authors.tmp"; then
        echo "Предупреждение: ошибка при обработке $file" >&2
        continue
    fi
    
    # Подсчитываем количество строк для каждого автора (каждая строка файла дает одну запись author)
    sort "$TEMP_DIR/file_authors.tmp" | uniq -c > "$TEMP_DIR/file_authors_counted.tmp"
    cat "$TEMP_DIR/file_authors_counted.tmp" >> "$TEMP_DIR/author_lines.tmp"
done

if [[ ! -f "$TEMP_DIR/author_lines.tmp" ]] || [[ ! -s "$TEMP_DIR/author_lines.tmp" ]]; then
    echo "Авторы не найдены"
    exit 0
fi

# Логирование для отладки
echo "TOTAL_LINES: $TOTAL_LINES" >> "$DEBUG_LOG"

# Проверка деления на ноль
if [[ $TOTAL_LINES -eq 0 ]]; then
    echo "Ошибка: TOTAL_LINES равен 0, деление на ноль невозможно" >&2
    echo "Данные о количестве строк отсутствуют" >> "$DEBUG_LOG"
    exit 1
fi

while read -r count author; do
    ((authors_total["$author"] += count)) || true
done < "$TEMP_DIR/author_lines.tmp"

echo ""
echo "=== АВТОРСТВО СТРОК (git blame) ==="
echo "Обработано файлов: ${#FILES[@]}"
echo "Всего строк: $TOTAL_LINES"
echo ""
printf "%-30s %10s %8s\n" "Автор" "Строк" "% всего"
printf "%-30s %10s %8s\n" "------------------------------" "----------" "--------"

if [ ${#authors_total[@]} -eq 0 ]; then
    echo "Авторы не найдены"
else
    # Логирование для отладки
    echo "Количество авторов: ${#authors_total[@]}" >> "$DEBUG_LOG"
    
    for author in "${!authors_total[@]}"; do
        percent=$((authors_total["$author"] * 100 / TOTAL_LINES))
        echo "Автор: $author, Строк: ${authors_total[$author]}, Процент: $percent%" >> "$DEBUG_LOG"
        printf "%-30s %10d %7s%%\n" "$author" "${authors_total[$author]}" "$percent"
    done | sort -k2 -rn
fi

echo ""
echo "=== ТОП-5 АВТОРОВ ==="
sorted_authors=$(for author in "${!authors_total[@]}"; do
    echo "${authors_total[$author]} $author"
done | sort -rn)

echo "$sorted_authors" | head -5 | while read -r count author; do
    percent=$((count * 100 / TOTAL_LINES))
    echo "  $author: $count строк ($percent%)"
done

# Логирование для отладки
echo "ТОП-5 авторов:" >> "$DEBUG_LOG"
echo "$sorted_authors" | head -5 | while read -r count author; do
    percent=$((count * 100 / TOTAL_LINES))
    echo "  $author: $count строк ($percent%)" >> "$DEBUG_LOG"
done
