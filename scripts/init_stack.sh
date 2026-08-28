#!/bin/bash
set -e

STACK_NAME=$1
TOOL=${2:-kubernetes}
TOOLING_NAME=${3:-Kubernetes}
TOTAL_STEPS=${4:-15}

if [ -z "$STACK_NAME" ]; then
    echo "Usage: $0 <stack_name> [tool] [tooling_name] [total_steps]"
    echo "Example: $0 kubernetes kubectl 'Kubernetes' 15"
    exit 1
fi

if [ -d "stacks/$STACK_NAME" ]; then
    echo "La stack $STACK_NAME existe déjà."
    exit 1
fi

if [ ! -d "templates/stack_template" ]; then
    echo "Le template templates/stack_template est manquant."
    exit 1
fi

echo "Création de la stack : $STACK_NAME (outil: $TOOL, tooling: $TOOLING_NAME, étapes: $TOTAL_STEPS)"

mkdir -p stacks
cp -r templates/stack_template "stacks/$STACK_NAME"

LAST_UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 << PY
import re
from pathlib import Path

stack = "$STACK_NAME"
tool = "$TOOL"
tooling = "$TOOLING_NAME"
total_steps = "$TOTAL_STEPS"
last_updated = "$LAST_UPDATED"

root = Path("stacks") / stack
for p in root.rglob("*"):
    if p.is_file():
        text = p.read_text(encoding="utf-8")
        text = text.replace("{STACK_NAME}", stack)
        text = text.replace("{TOOL}", tool)
        text = text.replace("{TOOLING_NAME}", tooling)
        text = text.replace("{TOTAL_STEPS}", total_steps)
        text = text.replace("{LAST_UPDATED}", last_updated)
        p.write_text(text, encoding="utf-8")
PY

echo "Stack $STACK_NAME créée dans stacks/$STACK_NAME"
echo "Prochaines étapes :"
echo "   1. Remplir resources/book_toc.md et resources/kodekloud_modules.md"
echo "   2. Adapter roadmap.yaml et test_strategy.yaml"
echo "   3. Vérifier que prompts/ correspondent à ton outil"
