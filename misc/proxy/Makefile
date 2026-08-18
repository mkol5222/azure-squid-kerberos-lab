SQUID_CONF = /etc/squid/squid.conf
SQUID_DIR = /etc/squid
BACKUP_SUFFIX = $(shell date +%Y%m%d_%H%M%S)

.PHONY: proxy-auth proxy-noauth proxy-status

proxy-auth:
	@echo "Backing up current config..."
	@sudo cp $(SQUID_CONF) $(SQUID_DIR)/squid.conf.bak.$(BACKUP_SUFFIX)
	@echo "Deploying authenticated config..."
	@sudo cp $(SQUID_DIR)/squid.conf.authenticated $(SQUID_CONF)
	@sudo systemctl restart squid
	@echo "Squid restarted with AUTHENTICATED mode."

proxy-noauth:
	@echo "Backing up current config..."
	@sudo cp $(SQUID_CONF) $(SQUID_DIR)/squid.conf.bak.$(BACKUP_SUFFIX)
	@echo "Deploying unauthenticated config..."
	@sudo cp $(SQUID_DIR)/squid.conf.unauthenticated $(SQUID_CONF)
	@sudo systemctl restart squid
	@echo "Squid restarted with UNAUTHENTICATED mode."

proxy-status:
	@sudo systemctl status squid --no-pager
