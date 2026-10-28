# Tests unitaires des briques validées localement (sans registre ni réseau).
# Les bancs (poc/bricks/*/bench.sh) demandent un registre local et des outils :
# voir le README de chaque brique.
.PHONY: test reuse
test:
	cd poc/bricks/01-forgejo-sync && python3 -m unittest -q test_sync
	cd tools/index && python3 -m unittest -q test_index
	cd poc/bricks/13a-licences && python3 -m unittest -q test_licences

# Conformité REUSE du dépôt (outil reuse ≥ 4, qui lit REUSE.toml).
reuse:
	reuse lint
