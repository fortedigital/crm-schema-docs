# Salesforce CRM — Object Reference (Sample)

> **Sample data only.** Represents a standard Salesforce Sales Cloud and Service Cloud org.
> Run the pipeline against your own Salesforce org to produce real output.

_Generated: 2026-03-05_

---

## Diagrams

### Salesforce — Core Entities

_Diagram image not available — run the generate stage to render PNGs._

### Salesforce — Sales Process

_Diagram image not available — run the generate stage to render PNGs._

### Salesforce — Activities

_Diagram image not available — run the generate stage to render PNGs._

### Salesforce — Service

_Diagram image not available — run the generate stage to render PNGs._

---

## Object Definitions

### Account

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Account ID | id | yes | no | 10 |
| Name | Account Name | string | yes | no | 12 |
| Phone | Phone | phone | no | no | 8 |
| Website | Website | url | no | no | 3 |
| Industry | Industry | picklist | no | no | 5 |
| Type | Account Type | picklist | no | no | 6 |
| AnnualRevenue | Annual Revenue | currency | no | no | 3 |
| NumberOfEmployees | Employees | integer | no | no | 2 |
| BillingStreet | Billing Street | textarea | no | no | 4 |
| BillingCity | Billing City | string | no | no | 4 |
| BillingState | Billing State | string | no | no | 4 |
| BillingPostalCode | Billing Zip/Postal Code | string | no | no | 4 |
| BillingCountry | Billing Country | string | no | no | 4 |
| ParentId | Parent Account | reference | no | no | 2 |
| AccountSource | Account Source | picklist | no | no | 3 |
| Rating | Rating | picklist | no | no | 2 |
| OwnerId | Owner | reference | yes | no | 10 |

### Contact

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Contact ID | id | yes | no | 10 |
| FirstName | First Name | string | no | no | 8 |
| LastName | Last Name | string | yes | no | 10 |
| Email | Email | email | no | no | 9 |
| Phone | Phone | phone | no | no | 7 |
| MobilePhone | Mobile | phone | no | no | 5 |
| Title | Title | string | no | no | 6 |
| Department | Department | string | no | no | 4 |
| AccountId | Account | reference | no | no | 9 |
| ReportsToId | Reports To | reference | no | no | 2 |
| Birthdate | Birthdate | date | no | no | 1 |
| LeadSource | Lead Source | picklist | no | no | 4 |
| OwnerId | Owner | reference | yes | no | 10 |

### Lead

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Lead ID | id | yes | no | 8 |
| FirstName | First Name | string | no | no | 6 |
| LastName | Last Name | string | yes | no | 8 |
| Email | Email | email | no | no | 7 |
| Phone | Phone | phone | no | no | 5 |
| MobilePhone | Mobile | phone | no | no | 3 |
| Company | Company | string | yes | no | 8 |
| Title | Title | string | no | no | 4 |
| LeadSource | Lead Source | picklist | no | no | 5 |
| Status | Status | picklist | yes | no | 8 |
| Rating | Rating | picklist | no | no | 3 |
| Industry | Industry | picklist | no | no | 4 |
| AnnualRevenue | Annual Revenue | currency | no | no | 2 |
| IsConverted | Converted | boolean | no | no | 4 |
| OwnerId | Owner | reference | yes | no | 8 |

### Opportunity

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Opportunity ID | id | yes | no | 10 |
| Name | Opportunity Name | string | yes | no | 10 |
| AccountId | Account | reference | no | no | 9 |
| StageName | Stage | picklist | yes | no | 10 |
| CloseDate | Close Date | date | yes | no | 10 |
| Amount | Amount | currency | no | no | 9 |
| Probability | Probability (%) | double | no | no | 7 |
| LeadSource | Lead Source | picklist | no | no | 4 |
| Type | Opportunity Type | picklist | no | no | 5 |
| Description | Description | textarea | no | no | 3 |
| ForecastCategory | Forecast Category | picklist | no | no | 6 |
| Pricebook2Id | Price Book | reference | no | no | 4 |
| OwnerId | Owner | reference | yes | no | 10 |

### OpportunityLineItem

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Line Item ID | id | yes | no | 5 |
| OpportunityId | Opportunity | reference | yes | no | 5 |
| PricebookEntryId | Price Book Entry | reference | yes | no | 5 |
| Product2Id | Product | reference | no | no | 5 |
| Quantity | Quantity | double | yes | no | 5 |
| UnitPrice | Sales Price | currency | no | no | 5 |
| TotalPrice | Total Price | currency | no | no | 5 |
| ListPrice | List Price | currency | no | no | 3 |
| Discount | Discount | double | no | no | 3 |
| Description | Description | textarea | no | no | 2 |
| ServiceDate | Date | date | no | no | 2 |

### Product2

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Product ID | id | yes | no | 6 |
| Name | Product Name | string | yes | no | 6 |
| ProductCode | Product Code | string | no | no | 5 |
| Description | Description | textarea | no | no | 3 |
| Family | Product Family | picklist | no | no | 4 |
| IsActive | Active | boolean | yes | no | 5 |

### Pricebook2

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Price Book ID | id | yes | no | 4 |
| Name | Price Book Name | string | yes | no | 4 |
| Description | Description | textarea | no | no | 2 |
| IsActive | Active | boolean | yes | no | 4 |
| IsStandard | Is Standard Price Book | boolean | no | no | 3 |

### PricebookEntry

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Pricebook Entry ID | id | yes | no | 4 |
| Pricebook2Id | Price Book | reference | yes | no | 4 |
| Product2Id | Product | reference | yes | no | 4 |
| UnitPrice | List Price | currency | yes | no | 4 |
| IsActive | Active | boolean | yes | no | 4 |
| UseStandardPrice | Use Standard Price | boolean | no | no | 3 |
| CurrencyIsoCode | Currency | string | no | no | 3 |

### Quote

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Quote ID | id | yes | no | 6 |
| Name | Quote Name | string | yes | no | 6 |
| QuoteNumber | Quote Number | autonumber | yes | no | 6 |
| OpportunityId | Opportunity | reference | no | no | 6 |
| Pricebook2Id | Price Book | reference | no | no | 4 |
| TotalPrice | Total Price | currency | no | no | 6 |
| Discount | Discount | double | no | no | 2 |
| Tax | Tax | currency | no | no | 2 |
| GrandTotal | Grand Total | currency | no | no | 6 |
| ExpirationDate | Expiration Date | date | no | no | 4 |
| Status | Status | picklist | yes | no | 6 |
| OwnerId | Owner | reference | yes | no | 6 |

### QuoteLineItem

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Quote Line Item ID | id | yes | no | 4 |
| QuoteId | Quote | reference | yes | no | 4 |
| PricebookEntryId | Price Book Entry | reference | yes | no | 4 |
| Product2Id | Product | reference | no | no | 4 |
| Quantity | Quantity | double | yes | no | 4 |
| UnitPrice | Sales Price | currency | no | no | 4 |
| TotalPrice | Total Price | currency | no | no | 4 |
| Discount | Discount | double | no | no | 2 |
| Description | Description | textarea | no | no | 2 |
| ServiceDate | Date | date | no | no | 2 |

### Case

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Case ID | id | yes | no | 8 |
| CaseNumber | Case Number | autonumber | yes | no | 8 |
| Subject | Subject | string | no | no | 8 |
| Description | Description | textarea | no | no | 5 |
| AccountId | Account | reference | no | no | 8 |
| ContactId | Contact | reference | no | no | 8 |
| Type | Type | picklist | no | no | 6 |
| Priority | Priority | picklist | no | no | 7 |
| Origin | Case Origin | picklist | no | no | 6 |
| Status | Status | picklist | yes | no | 8 |
| Reason | Case Reason | picklist | no | no | 5 |
| IsEscalated | Escalated | boolean | no | no | 4 |
| OwnerId | Owner | reference | yes | no | 8 |

### Task

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Task ID | id | yes | no | 7 |
| Subject | Subject | string | no | no | 7 |
| WhoId | Name (Who) | reference | no | no | 6 |
| WhatId | Related To (What) | reference | no | no | 6 |
| ActivityDate | Due Date | date | no | no | 7 |
| Status | Status | picklist | yes | no | 7 |
| Priority | Priority | picklist | yes | no | 7 |
| Description | Comments | textarea | no | no | 4 |
| OwnerId | Owner | reference | yes | no | 7 |

### Event

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Event ID | id | yes | no | 5 |
| Subject | Subject | string | no | no | 5 |
| WhoId | Name (Who) | reference | no | no | 4 |
| WhatId | Related To (What) | reference | no | no | 4 |
| StartDateTime | Start | datetime | yes | no | 5 |
| EndDateTime | End | datetime | yes | no | 5 |
| ActivityDate | Date | date | no | no | 5 |
| DurationInMinutes | Duration | integer | no | no | 4 |
| Location | Location | string | no | no | 3 |
| Description | Description | textarea | no | no | 3 |
| IsAllDayEvent | All Day | boolean | no | no | 4 |
| OwnerId | Owner | reference | yes | no | 5 |

### EmailMessage

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Email Message ID | id | yes | no | 4 |
| ParentId | Parent | reference | no | no | 4 |
| Subject | Subject | string | no | no | 4 |
| FromAddress | From Address | email | no | no | 4 |
| ToAddress | To Address | string | no | no | 4 |
| TextBody | Text Body | textarea | no | no | 3 |
| HtmlBody | HTML Body | textarea | no | no | 3 |
| MessageDate | Message Date | datetime | no | no | 4 |
| Incoming | Incoming | boolean | no | no | 3 |

### KnowledgeArticle

| api_name | label | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| Id | Knowledge Article ID | id | yes | no | 4 |
| Title | Title | string | yes | no | 4 |
| Summary | Summary | textarea | no | no | 3 |
| ArticleNumber | Article Number | autonumber | yes | no | 4 |
| LastPublishedDate | Last Published | datetime | no | no | 3 |
| PublishStatus | Publish Status | picklist | yes | no | 4 |
| Language | Language | picklist | yes | no | 4 |
| IsVisibleInApp | Visible in App | boolean | no | no | 2 |
| IsVisibleInCsp | Visible in Customer Portal | boolean | no | no | 2 |
| OwnerId | Owner | reference | yes | no | 4 |
