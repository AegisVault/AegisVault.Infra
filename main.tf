# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

// !
resource "azurerm_resource_group" "rg" {
  name     = "hkthn-tal-aegisvault"
  location = "australiaeast"
  tags = {
    "owner" = "lwoollett@jadeworld.com"
  }
}

resource "azurerm_storage_account" "funcstorage" {
  name                     = "aegisvaultfuncstorage"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
resource "azurerm_storage_account" "datastorage" {
  name                     = "aegisvaultstorage"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
}
resource "azurerm_storage_container" "datastorage-container" {
  name                  = "documentstorage"
  storage_account_name  = azurerm_storage_account.datastorage.name
  container_access_type = "private"
}

resource "azurerm_service_plan" "svplan" {
  name                = "aegisvaultsrvpln"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Windows"
  sku_name            = "Y1"
}

resource "azurerm_windows_function_app" "func-create" {
  name                = "aegisvault-func-create"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.funcstorage.name
  storage_account_access_key = azurerm_storage_account.funcstorage.primary_access_key
  service_plan_id            = azurerm_service_plan.svplan.id
  app_settings = {
    "STORAGE_CONNECTION_STRING"  = azurerm_storage_account.datastorage.primary_connection_string
    "STORAGE_CONTAINER_NAME"     = azurerm_storage_container.datastorage-container.name
    "COSMOSDB_CONNECTION_STRING" = azurerm_cosmosdb_account.db.connection_strings[0]
    "SEND_EMAIL_API_URL"         = azurerm_windows_function_app.func-email.default_hostname
    "SEND_EMAIL_API_KEY"         = "GET YOUR OWN"
  }

  site_config {}
}
resource "azurerm_windows_function_app" "func-retrieve" {
  name                = "aegisvault-func-retrieve"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.funcstorage.name
  storage_account_access_key = azurerm_storage_account.funcstorage.primary_access_key
  service_plan_id            = azurerm_service_plan.svplan.id

  app_settings = {
    "STORAGE_CONNECTION_STRING"  = azurerm_storage_account.datastorage.primary_connection_string
    "STORAGE_CONTAINER_NAME"     = azurerm_storage_container.datastorage-container.name
    "COSMOSDB_CONNECTION_STRING" = azurerm_cosmosdb_account.db.connection_strings[0]
  }
  site_config {}
}
resource "azurerm_windows_function_app" "func-email" {
  name                = "aegisvault-func-email"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.funcstorage.name
  storage_account_access_key = azurerm_storage_account.funcstorage.primary_access_key
  service_plan_id            = azurerm_service_plan.svplan.id

  site_config {}

  app_settings = {
    "OPENAI_API_KEY"        = "GET YOUR OWN"
    "ACS_CONNECTION_STRING" = "GET YOUR OWN"
  }
}

// ! Normally we'd have our static site custom domain information in here but
// ! i'm not commiting that to gh
resource "azurerm_static_site" "webhost" {
  name                = "aegisvault-ui"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_cosmosdb_account" "db" {
  name                = "aegisvault-db"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"

  enable_automatic_failover = true


  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }

  geo_location {
    location          = "australiaeast"
    failover_priority = 1
  }

  geo_location {
    location          = "australiasoutheast"
    failover_priority = 0
  }
}
