@AbapCatalog.sqlViewName: 'ZISALESORDHEADTP'
@AbapCatalog.compiler.compareFilter: true
@AbapCatalog.preserveKey: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Sales Order Header Interface View'
@ObjectModel.representativeKey: 'SalesOrder'

define view Z_I_SalesOrderHeader_TP
  as select from vbak
  association [0..*] to Z_I_SalesOrderItem_TP as _Item on $projection.SalesOrder = _Item.SalesOrder
{
  key vbeln                          as SalesOrder,
      auart                          as SalesOrderType,
      vkorg                          as SalesOrganization,
      vtweg                          as DistributionChannel,
      spart                          as Division,
      kunnr                          as SoldToParty,
      bstnk                          as PurchaseOrderByCustomer,
      vdatu                          as RequestedDeliveryDate,
      gbstk                          as OverallSDProcessStatus,
      netwr                          as TotalNetAmount,
      waerk                          as Currency,
      ernam                          as CreatedByUser,
      erdat                          as CreationDate,
      aenam                          as LastChangedByUser,
      aedat                          as LastChangeDate,
      _Item
}
