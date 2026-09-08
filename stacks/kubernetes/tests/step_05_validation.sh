#!/usr/bin/env bash
set -euo pipefail

ADR_FILE="stacks/kubernetes/adrs/adr_step_05_final.md"
QUOTA_DIR="stacks/kubernetes/infra/base/resource_quotas"
LIMIT_DIR="stacks/kubernetes/infra/base/limit_ranges"

quota_files=(
  "${QUOTA_DIR}/resourcequota_dev.yaml"
  "${QUOTA_DIR}/resourcequota_staging.yaml"
  "${QUOTA_DIR}/resourcequota_prod.yaml"
  "${QUOTA_DIR}/resourcequota_tools.yaml"
)

limit_files=(
  "${LIMIT_DIR}/limitrange_dev.yaml"
  "${LIMIT_DIR}/limitrange_staging.yaml"
  "${LIMIT_DIR}/limitrange_prod.yaml"
  "${LIMIT_DIR}/limitrange_tools.yaml"
)

fail() {
  echo "❌ $1" >&2
  exit 1
}

# 1. ADR exists and contains key markers
test -f "$ADR_FILE" || fail "ADR file not found: $ADR_FILE"

grep -q "ADR-0005" "$ADR_FILE" || fail "ADR must contain 'ADR-0005'"
grep -q "ResourceQuota" "$ADR_FILE" || fail "ADR must mention ResourceQuota"
grep -q "LimitRange" "$ADR_FILE" || fail "ADR must mention LimitRange"

for ns in dev staging prod tools; do
  grep -q "$ns" "$ADR_FILE" || fail "ADR must mention namespace '$ns'"
done

# 2. All YAML files exist
for f in "${quota_files[@]}" "${limit_files[@]}"; do
  test -f "$f" || fail "Missing required file: $f"
done

# 3. Each YAML file has correct kind and namespace
check_quota_ns() {
  local file="$1"
  local expected_ns="$2"
  grep -q "kind: ResourceQuota" "$file" || fail "$file must contain 'kind: ResourceQuota'"
  grep -q "namespace: ${expected_ns}" "$file" || fail "$file must contain namespace '$expected_ns'"
}

check_limit_ns() {
  local file="$1"
  local expected_ns="$2"
  grep -q "kind: LimitRange" "$file" || fail "$file must contain 'kind: LimitRange'"
  grep -q "namespace: ${expected_ns}" "$file" || fail "$file must contain namespace '$expected_ns'"
}

check_quota_ns "${QUOTA_DIR}/resourcequota_dev.yaml" "dev"
check_quota_ns "${QUOTA_DIR}/resourcequota_staging.yaml" "staging"
check_quota_ns "${QUOTA_DIR}/resourcequota_prod.yaml" "prod"
check_quota_ns "${QUOTA_DIR}/resourcequota_tools.yaml" "tools"

check_limit_ns "${LIMIT_DIR}/limitrange_dev.yaml" "dev"
check_limit_ns "${LIMIT_DIR}/limitrange_staging.yaml" "staging"
check_limit_ns "${LIMIT_DIR}/limitrange_prod.yaml" "prod"
check_limit_ns "${LIMIT_DIR}/limitrange_tools.yaml" "tools"

# 4. Quota YAML contains spec.hard with at least one quota key
for f in "${quota_files[@]}"; do
  grep -q "spec:" "$f" || fail "$f must contain 'spec:'"
  grep -q "hard:" "$f" || fail "$f must contain 'hard:'"
  grep -q "requests.cpu" "$f" || fail "$f must contain 'requests.cpu' quota"
done

# 5. LimitRange YAML contains spec.limits and default/defaultRequest
for f in "${limit_files[@]}"; do
  grep -q "spec:" "$f" || fail "$f must contain 'spec:'"
  grep -q "limits:" "$f" || fail "$f must contain 'limits:'"
  grep -q "default:" "$f" || fail "$f must contain 'default:' in LimitRange"
done

# 6. Optional: YAML syntax validation if python3 + PyYAML is available
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
try:
    import yaml
except ImportError:
    print("⚠️  PyYAML not installed, skipping YAML syntax validation")
    raise SystemExit(0)

paths = [
    "stacks/kubernetes/infra/base/resource_quotas/resourcequota_dev.yaml",
    "stacks/kubernetes/infra/base/resource_quotas/resourcequota_staging.yaml",
    "stacks/kubernetes/infra/base/resource_quotas/resourcequota_prod.yaml",
    "stacks/kubernetes/infra/base/resource_quotas/resourcequota_tools.yaml",
    "stacks/kubernetes/infra/base/limit_ranges/limitrange_dev.yaml",
    "stacks/kubernetes/infra/base/limit_ranges/limitrange_staging.yaml",
    "stacks/kubernetes/infra/base/limit_ranges/limitrange_prod.yaml",
    "stacks/kubernetes/infra/base/limit_ranges/limitrange_tools.yaml",
]

for p in paths:
    try:
        with open(p, 'r') as f:
            yaml.safe_load(f)
    except Exception as e:
        print(f"Invalid YAML in {p}: {e}")
        raise SystemExit(1)
PY
fi

echo "✅ Step 05 validation passed"
exit 0
