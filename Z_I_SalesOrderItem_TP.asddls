@AbapCatalog.sqlViewName: 'ZISALESORDITEMTP'
@AbapCatalog.compiler.compareFilter: true
@AbapCatalog.preserveKey: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Sales Order Item Interface View'
@ObjectModel.representativeKey: 'SalesOrderItem'

define view Z_I_SalesOrderItem_TP
  as select from vbap
  association [1..1] to Z_I_SalesOrderHeader_TP as _Header on $projection.SalesOrder = _Header.SalesOrder
{
  key vbeln as SalesOrder,
  key posnr as SalesOrderItem,
      matnr as Material,
      arktx as OrderItemText,
      kwmeng as OrderQuantity,
      zieme as TargetQuantityUnit,
      netwr as NetAmount,
      waerk as Currency,
      _Header
}
