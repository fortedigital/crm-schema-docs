# Dynamics 365 CRM — Entity Reference

_Generated: 2026-03-03 13:42_

---

## Diagrams

### Dynamics 365 — Activities

_Diagram image not available._

### Dynamics 365 — Core Entities

_Diagram image not available._

### Dynamics 365 — Sales Process

_Diagram image not available._

### Dynamics 365 — Service

_Diagram image not available._

---

## Entity Definitions

### account

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| accountid | Account ID | guid | yes |
| name | Account Name | string | yes |
| emailaddress1 | Email | string | no |
| telephone1 | Phone | string | no |
| websiteurl | Website | string | no |
| address1_line1 | Street 1 | string | no |
| address1_city | City | string | no |
| address1_country | Country | string | no |
| industrycode | Industry | picklist | no |
| revenue | Annual Revenue | decimal | no |
| numberofemployees | Number of Employees | int | no |
| ownerid | Owner | guid | yes |
| statecode | Status | picklist | yes |

### contact

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| contactid | Contact ID | guid | yes |
| firstname | First Name | string | no |
| lastname | Last Name | string | yes |
| emailaddress1 | Email | string | no |
| telephone1 | Phone | string | no |
| mobilephone | Mobile Phone | string | no |
| address1_line1 | Street 1 | string | no |
| address1_city | City | string | no |
| birthdate | Birthday | date | no |
| gendercode | Gender | picklist | no |
| parentcustomerid | Account | guid | no |
| ownerid | Owner | guid | yes |
| statecode | Status | picklist | yes |

### lead

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| leadid | Lead ID | guid | yes |
| firstname | First Name | string | no |
| lastname | Last Name | string | yes |
| emailaddress1 | Email | string | no |
| telephone1 | Phone | string | no |
| companyname | Company | string | yes |
| subject | Topic | string | yes |
| leadqualitycode | Rating | picklist | no |
| leadsourcecode | Lead Source | picklist | no |
| estimatedvalue | Est. Revenue | decimal | no |
| estimatedclosedate | Est. Close Date | date | no |
| ownerid | Owner | guid | yes |
| statecode | Status | picklist | yes |

### opportunity

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| opportunityid | Opportunity ID | guid | yes |
| name | Topic | string | yes |
| parentaccountid | Account | guid | no |
| parentcontactid | Contact | guid | no |
| estimatedvalue | Est. Revenue | decimal | no |
| actualvalue | Actual Revenue | decimal | no |
| estimatedclosedate | Est. Close Date | date | yes |
| actualclosedate | Actual Close Date | date | no |
| closeprobability | Probability | int | no |
| stepname | Pipeline Phase | string | no |
| salesstage | Sales Stage | picklist | no |
| ownerid | Owner | guid | yes |
| statecode | Status | picklist | yes |

### quote

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| quoteid | Quote ID | guid | yes |
| name | Name | string | yes |
| quotenumber | Quote Number | string | yes |
| opportunityid | Opportunity | guid | no |
| accountid | Account | guid | no |
| totallineitemamount | Total Detail Amount | decimal | no |
| discountamount | Quote Discount | decimal | no |
| freightamount | Freight Amount | decimal | no |
| totaltax | Total Tax | decimal | no |
| totalamount | Total Amount | decimal | no |
| effectivefrom | Effective From | date | no |
| effectiveto | Effective To | date | no |
| statecode | Status | picklist | yes |

### quotedetail

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| quotedetailid | Quote Line ID | guid | yes |
| quoteid | Quote | guid | yes |
| productid | Product | guid | no |
| productdescription | Description | string | no |
| quantity | Quantity | decimal | yes |
| priceperunit | Price Per Unit | decimal | no |
| manualdiscountamount | Manual Discount | decimal | no |
| extendedamount | Extended Amount | decimal | no |

### salesorder

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| salesorderid | Order ID | guid | yes |
| name | Name | string | yes |
| ordernumber | Order Number | string | yes |
| quoteid | Quote | guid | no |
| accountid | Account | guid | no |
| totallineitemamount | Total Detail Amount | decimal | no |
| discountamount | Order Discount | decimal | no |
| freightamount | Freight Amount | decimal | no |
| totaltax | Total Tax | decimal | no |
| totalamount | Total Amount | decimal | no |
| submitdate | Date Submitted | date | no |
| statecode | Status | picklist | yes |

### salesorderdetail

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| salesorderdetailid | Order Line ID | guid | yes |
| salesorderid | Order | guid | yes |
| productid | Product | guid | no |
| productdescription | Description | string | no |
| quantity | Quantity | decimal | yes |
| priceperunit | Price Per Unit | decimal | no |
| manualdiscountamount | Manual Discount | decimal | no |
| extendedamount | Extended Amount | decimal | no |

### invoice

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| invoiceid | Invoice ID | guid | yes |
| name | Name | string | yes |
| invoicenumber | Invoice Number | string | yes |
| salesorderid | Order | guid | no |
| accountid | Account | guid | no |
| totallineitemamount | Total Detail Amount | decimal | no |
| discountamount | Invoice Discount | decimal | no |
| freightamount | Freight Amount | decimal | no |
| totaltax | Total Tax | decimal | no |
| totalamount | Total Amount | decimal | no |
| duedate | Due Date | date | no |
| statecode | Status | picklist | yes |

### invoicedetail

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| invoicedetailid | Invoice Line ID | guid | yes |
| invoiceid | Invoice | guid | yes |
| productid | Product | guid | no |
| productdescription | Description | string | no |
| quantity | Quantity | decimal | yes |
| priceperunit | Price Per Unit | decimal | no |
| manualdiscountamount | Manual Discount | decimal | no |
| extendedamount | Extended Amount | decimal | no |

### product

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| productid | Product ID | guid | yes |
| name | Name | string | yes |
| productnumber | Product Number | string | yes |
| uomid | Unit | guid | yes |
| uomscheduleid | Unit Group | guid | yes |
| price | List Price | decimal | no |
| standardcost | Standard Cost | decimal | no |
| currentcost | Current Cost | decimal | no |
| description | Description | string | no |
| statecode | Status | picklist | yes |

### activitypointer

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| activityid | Activity ID | guid | yes |
| subject | Subject | string | yes |
| activitytypecode | Activity Type | picklist | yes |
| regardingobjectid | Regarding | guid | no |
| regardingobjecttype | Regarding Type | string | no |
| ownerid | Owner | guid | yes |
| scheduledstart | Start | datetime | no |
| scheduledend | Due | datetime | no |
| actualstart | Actual Start | datetime | no |
| actualend | Actual End | datetime | no |
| statecode | Status | picklist | yes |
| statuscode | Status Reason | picklist | yes |

### email

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| activityid | Activity ID | guid | yes |
| subject | Subject | string | no |
| description | Body | string | no |
| trackingtoken | Tracking Token | string | no |
| senton | Sent On | datetime | no |
| directioncode | Direction | bool | no |
| statecode | Status | picklist | yes |

### phonecall

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| activityid | Activity ID | guid | yes |
| subject | Subject | string | yes |
| description | Description | string | no |
| phonenumber | Phone Number | string | no |
| directioncode | Direction | bool | no |
| scheduledend | Due | datetime | no |
| statecode | Status | picklist | yes |

### task

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| activityid | Activity ID | guid | yes |
| subject | Subject | string | yes |
| description | Description | string | no |
| percentcomplete | Percent Complete | int | no |
| scheduledend | Due | datetime | no |
| statecode | Status | picklist | yes |

### appointment

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| activityid | Activity ID | guid | yes |
| subject | Subject | string | yes |
| description | Description | string | no |
| location | Location | string | no |
| scheduledstart | Start | datetime | yes |
| scheduledend | End | datetime | yes |
| isalldayevent | All Day Event | bool | no |
| statecode | Status | picklist | yes |

### activityparty

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| activitypartyid | Activity Party ID | guid | yes |
| activityid | Activity | guid | yes |
| partyid | Party | guid | no |
| partyobjecttypecode | Party Type | string | no |
| participationtypemask | Participation Type | picklist | yes |
| addressused | Address | string | no |

### incident

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| incidentid | Case ID | guid | yes |
| title | Case Title | string | yes |
| description | Description | string | no |
| customerid | Customer | guid | yes |
| customeridtype | Customer Type | string | yes |
| primarycontactid | Contact | guid | no |
| casetypecode | Case Type | picklist | no |
| prioritycode | Priority | picklist | no |
| caseorigincode | Origin | picklist | no |
| productid | Product | guid | no |
| subjectid | Subject | guid | no |
| resolvedon | Resolved On | datetime | no |
| ownerid | Owner | guid | yes |
| statecode | Status | picklist | yes |
| statuscode | Status Reason | picklist | yes |

### knowledgearticle

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| knowledgearticleid | Article ID | guid | yes |
| title | Title | string | yes |
| keywords | Keywords | string | no |
| content | Content | string | no |
| languagelocaleid | Language | int | yes |
| articlepublicnumber | Article Number | int | no |
| isprimary | Primary Translation | bool | no |
| isinternal | Internal Only | bool | no |
| subjectid | Subject | guid | no |
| statecode | Status | picklist | yes |
| statuscode | Status Reason | picklist | yes |

### subject

| logical_name | display_name | type | required |
| --- | --- | --- | --- |
| subjectid | Subject ID | guid | yes |
| title | Title | string | yes |
| description | Description | string | no |
| parentsubject | Parent Subject | guid | no |

