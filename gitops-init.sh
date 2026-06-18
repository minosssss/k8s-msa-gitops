cd /home/msa/gitops

# Secret 파일 절대 안 올라가도록
cat > .gitignore << 'EOF'
*secret*.yaml
*-secret.yaml
EOF

# git 초기화
git init
git config user.email "minosssss@gmail.com"
git config user.name "minosssss"
git remote add origin https://github.com/minosssss/k8s-msa-gitops.git

# 파일 추가 전 Secret 빠졌는지 확인
git add .
git status
# ← Secret 파일 안 보이면 OK

git commit -m "feat: MSA 초기 배포 매니페스트"
git push -u origin main
