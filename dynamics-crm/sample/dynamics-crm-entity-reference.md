# Dynamics 365 CRM — Entity Reference (Sample)

> **Sample data only.** Generated against a standard Dynamics 365 Sales and Service demo environment.
> Run the pipeline against your own Dataverse environment to produce real output.

_Generated: 2026-03-05_

---

## Diagrams

### Dynamics 365 — Core Entities

_Diagram image not available — run the generate stage to render PNGs._

### Dynamics 365 — Sales Process

_Diagram image not available — run the generate stage to render PNGs._

### Dynamics 365 — Activities

_Diagram image not available — run the generate stage to render PNGs._

### Dynamics 365 — Service

_Diagram image not available — run the generate stage to render PNGs._

---

## Entity Definitions

### account

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| accountid | Account ID | guid | yes | no | 10 |
| name | Account Name | string | yes | no | 12 |
| emailaddress1 | Email | string | no | no | 6 |
| telephone1 | Phone | string | no | no | 8 |
| websiteurl | Website | string | no | no | 3 |
| address1_line1 | Street 1 | string | no | no | 5 |
| address1_city | City | string | no | no | 5 |
| address1_country | Country | string | no | no | 5 |
| industrycode | Industry | picklist | no | no | 4 |
| revenue | Annual Revenue | decimal | no | no | 3 |
| numberofemployees | Number of Employees | int | no | no | 2 |
| parentaccountid | Parent Account | guid | no | no | 2 |
| primarycontactid | Primary Contact | guid | no | no | 4 |
| ownerid | Owner | guid | yes | no | 10 |
| statecode | Status | picklist | yes | no | 10 |

### contact

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| contactid | Contact ID | guid | yes | no | 10 |
| firstname | First Name | string | no | no | 8 |
| lastname | Last Name | string | yes | no | 10 |
| emailaddress1 | Email | string | no | no | 9 |
| telephone1 | Phone | string | no | no | 7 |
| mobilephone | Mobile Phone | string | no | no | 5 |
| jobtitle | Job Title | string | no | no | 6 |
| department | Department | string | no | no | 4 |
| address1_line1 | Street 1 | string | no | no | 4 |
| address1_city | City | string | no | no | 4 |
| birthdate | Birthday | date | no | no | 1 |
| gendercode | Gender | picklist | no | no | 1 |
| parentcustomerid | Account | guid | no | no | 9 |
| ownerid | Owner | guid | yes | no | 10 |
| statecode | Status | picklist | yes | no | 10 |

### lead

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| leadid | Lead ID | guid | yes | no | 8 |
| firstname | First Name | string | no | no | 6 |
| lastname | Last Name | string | yes | no | 8 |
| emailaddress1 | Email | string | no | no | 7 |
| telephone1 | Phone | string | no | no | 5 |
| companyname | Company | string | yes | no | 8 |
| subject | Topic | string | yes | no | 8 |
| leadqualitycode | Rating | picklist | no | no | 4 |
| leadsourcecode | Lead Source | picklist | no | no | 5 |
| estimatedvalue | Est. Revenue | decimal | no | no | 2 |
| estimatedclosedate | Est. Close Date | date | no | no | 2 |
| ownerid | Owner | guid | yes | no | 8 |
| statecode | Status | picklist | yes | no | 8 |

### opportunity

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| opportunityid | Opportunity ID | guid | yes | no | 10 |
| name | Topic | string | yes | no | 10 |
| parentaccountid | Account | guid | no | no | 9 |
| parentcontactid | Contact | guid | no | no | 5 |
| estimatedvalue | Est. Revenue | decimal | no | no | 8 |
| actualvalue | Actual Revenue | decimal | no | no | 4 |
| estimatedclosedate | Est. Close Date | date | yes | no | 10 |
| actualclosedate | Actual Close Date | date | no | no | 3 |
| closeprobability | Probability | int | no | no | 6 |
| stepname | Pipeline Phase | string | no | no | 5 |
| salesstage | Sales Stage | picklist | no | no | 8 |
| pricelevelid | Price List | guid | no | no | 3 |
| ownerid | Owner | guid | yes | no | 10 |
| statecode | Status | picklist | yes | no | 10 |

### quote

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| quoteid | Quote ID | guid | yes | no | 8 |
| name | Name | string | yes | no | 8 |
| quotenumber | Quote Number | string | yes | no | 8 |
| opportunityid | Opportunity | guid | no | no | 7 |
| accountid | Account | guid | no | no | 7 |
| totallineitemamount | Total Detail Amount | decimal | no | no | 5 |
| discountamount | Quote Discount | decimal | no | no | 3 |
| freightamount | Freight Amount | decimal | no | no | 2 |
| totaltax | Total Tax | decimal | no | no | 3 |
| totalamount | Total Amount | decimal | no | no | 7 |
| effectivefrom | Effective From | date | no | no | 4 |
| effectiveto | Effective To | date | no | no | 4 |
| ownerid | Owner | guid | yes | no | 8 |
| statecode | Status | picklist | yes | no | 8 |

### quotedetail

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| quotedetailid | Quote Line ID | guid | yes | no | 5 |
| quoteid | Quote | guid | yes | no | 5 |
| productid | Product | guid | no | no | 5 |
| productdescription | Description | string | no | no | 4 |
| quantity | Quantity | decimal | yes | no | 5 |
| priceperunit | Price Per Unit | decimal | no | no | 5 |
| manualdiscountamount | Manual Discount | decimal | no | no | 2 |
| extendedamount | Extended Amount | decimal | no | no | 5 |

### salesorder

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| salesorderid | Order ID | guid | yes | no | 8 |
| name | Name | string | yes | no | 8 |
| ordernumber | Order Number | string | yes | no | 8 |
| quoteid | Quote | guid | no | no | 5 |
| accountid | Account | guid | no | no | 7 |
| totallineitemamount | Total Detail Amount | decimal | no | no | 4 |
| discountamount | Order Discount | decimal | no | no | 3 |
| freightamount | Freight Amount | decimal | no | no | 2 |
| totaltax | Total Tax | decimal | no | no | 3 |
| totalamount | Total Amount | decimal | no | no | 7 |
| submitdate | Date Submitted | date | no | no | 5 |
| fulfilledon | Date Fulfilled | date | no | no | 3 |
| ownerid | Owner | guid | yes | no | 8 |
| statecode | Status | picklist | yes | no | 8 |

### salesorderdetail

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| salesorderdetailid | Order Line ID | guid | yes | no | 5 |
| salesorderid | Order | guid | yes | no | 5 |
| productid | Product | guid | no | no | 5 |
| productdescription | Description | string | no | no | 4 |
| quantity | Quantity | decimal | yes | no | 5 |
| priceperunit | Price Per Unit | decimal | no | no | 5 |
| manualdiscountamount | Manual Discount | decimal | no | no | 2 |
| extendedamount | Extended Amount | decimal | no | no | 5 |

### invoice

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| invoiceid | Invoice ID | guid | yes | no | 8 |
| name | Name | string | yes | no | 8 |
| invoicenumber | Invoice Number | string | yes | no | 8 |
| salesorderid | Order | guid | no | no | 5 |
| accountid | Account | guid | no | no | 7 |
| totallineitemamount | Total Detail Amount | decimal | no | no | 4 |
| discountamount | Invoice Discount | decimal | no | no | 3 |
| freightamount | Freight Amount | decimal | no | no | 2 |
| totaltax | Total Tax | decimal | no | no | 3 |
| totalamount | Total Amount | decimal | no | no | 7 |
| duedate | Due Date | date | no | no | 6 |
| ownerid | Owner | guid | yes | no | 8 |
| statecode | Status | picklist | yes | no | 8 |

### invoicedetail

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| invoicedetailid | Invoice Line ID | guid | yes | no | 5 |
| invoiceid | Invoice | guid | yes | no | 5 |
| productid | Product | guid | no | no | 5 |
| productdescription | Description | string | no | no | 4 |
| quantity | Quantity | decimal | yes | no | 5 |
| priceperunit | Price Per Unit | decimal | no | no | 5 |
| manualdiscountamount | Manual Discount | decimal | no | no | 2 |
| extendedamount | Extended Amount | decimal | no | no | 5 |

### product

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| productid | Product ID | guid | yes | no | 8 |
| name | Name | string | yes | no | 8 |
| productnumber | Product Number | string | yes | no | 7 |
| uomid | Unit | guid | yes | no | 5 |
| uomscheduleid | Unit Group | guid | yes | no | 4 |
| pricelevelid | Default Price List | guid | no | no | 3 |
| price | List Price | decimal | no | no | 6 |
| standardcost | Standard Cost | decimal | no | no | 3 |
| currentcost | Current Cost | decimal | no | no | 3 |
| description | Description | string | no | no | 4 |
| statecode | Status | picklist | yes | no | 8 |

### activitypointer

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| activityid | Activity ID | guid | yes | no | 8 |
| subject | Subject | string | yes | no | 8 |
| activitytypecode | Activity Type | picklist | yes | no | 8 |
| regardingobjectid | Regarding | guid | no | no | 7 |
| regardingobjecttype | Regarding Type | string | no | no | 5 |
| ownerid | Owner | guid | yes | no | 8 |
| scheduledstart | Start | datetime | no | no | 5 |
| scheduledend | Due | datetime | no | no | 6 |
| actualstart | Actual Start | datetime | no | no | 3 |
| actualend | Actual End | datetime | no | no | 3 |
| statecode | Status | picklist | yes | no | 8 |
| statuscode | Status Reason | picklist | yes | no | 7 |

### email

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| activityid | Activity ID | guid | yes | no | 6 |
| subject | Subject | string | no | no | 6 |
| description | Body | string | no | no | 4 |
| trackingtoken | Tracking Token | string | no | no | 2 |
| senton | Sent On | datetime | no | no | 5 |
| directioncode | Direction | bool | no | no | 4 |
| statecode | Status | picklist | yes | no | 6 |

### phonecall

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| activityid | Activity ID | guid | yes | no | 5 |
| subject | Subject | string | yes | no | 5 |
| description | Description | string | no | no | 3 |
| phonenumber | Phone Number | string | no | no | 4 |
| directioncode | Direction | bool | no | no | 3 |
| scheduledend | Due | datetime | no | no | 4 |
| statecode | Status | picklist | yes | no | 5 |

### task

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| activityid | Activity ID | guid | yes | no | 7 |
| subject | Subject | string | yes | no | 7 |
| description | Description | string | no | no | 4 |
| percentcomplete | Percent Complete | int | no | no | 3 |
| scheduledend | Due | datetime | no | no | 6 |
| statecode | Status | picklist | yes | no | 7 |

### appointment

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| activityid | Activity ID | guid | yes | no | 6 |
| subject | Subject | string | yes | no | 6 |
| description | Description | string | no | no | 3 |
| location | Location | string | no | no | 4 |
| scheduledstart | Start | datetime | yes | no | 6 |
| scheduledend | End | datetime | yes | no | 6 |
| isalldayevent | All Day Event | bool | no | no | 3 |
| statecode | Status | picklist | yes | no | 6 |

### activityparty

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| activitypartyid | Activity Party ID | guid | yes | no | 4 |
| activityid | Activity | guid | yes | no | 4 |
| partyid | Party | guid | no | no | 4 |
| partyobjecttypecode | Party Type | string | no | no | 4 |
| participationtypemask | Participation Type | picklist | yes | no | 4 |
| addressused | Address | string | no | no | 2 |

### incident

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| incidentid | Case ID | guid | yes | no | 8 |
| title | Case Title | string | yes | no | 8 |
| description | Description | string | no | no | 5 |
| customerid | Customer | guid | yes | no | 8 |
| customeridtype | Customer Type | string | yes | no | 6 |
| primarycontactid | Contact | guid | no | no | 6 |
| casetypecode | Case Type | picklist | no | no | 5 |
| prioritycode | Priority | picklist | no | no | 7 |
| caseorigincode | Origin | picklist | no | no | 5 |
| productid | Product | guid | no | no | 4 |
| subjectid | Subject | guid | no | no | 4 |
| resolvedon | Resolved On | datetime | no | no | 4 |
| ownerid | Owner | guid | yes | no | 8 |
| statecode | Status | picklist | yes | no | 8 |
| statuscode | Status Reason | picklist | yes | no | 7 |

### knowledgearticle

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| knowledgearticleid | Article ID | guid | yes | no | 5 |
| title | Title | string | yes | no | 5 |
| keywords | Keywords | string | no | no | 3 |
| content | Content | string | no | no | 4 |
| languagelocaleid | Language | int | yes | no | 4 |
| articlepublicnumber | Article Number | string | no | no | 4 |
| isprimary | Primary Translation | bool | no | no | 2 |
| isinternal | Internal Only | bool | no | no | 3 |
| subjectid | Subject | guid | no | no | 3 |
| statecode | Status | picklist | yes | no | 5 |
| statuscode | Status Reason | picklist | yes | no | 5 |

### subject

| logical_name | display_name | type | required | is_custom | usage |
| --- | --- | --- | --- | --- | --- |
| subjectid | Subject ID | guid | yes | no | 4 |
| title | Title | string | yes | no | 4 |
| description | Description | string | no | no | 2 |
| parentsubjectid | Parent Subject | guid | no | no | 2 |
