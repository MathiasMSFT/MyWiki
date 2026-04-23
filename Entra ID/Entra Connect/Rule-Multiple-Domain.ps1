IIF(IsPresent([userPrincipalName]),
IIF(CBool(
   IIF(
      InStr(LCase([userPrincipalName]),"@client.techno.ramq.gouv.qc.ca")=0),
      "Member",
      "Guest"),
   
   InStr(LCase([userPrincipalName]),"@ext.techno.ramq.gouv.qc.ca")=0),"Member","Guest")),
Error("UserPrincipalName is not present to determine UserType"))


IIF(IsPresent([userPrincipalName]) = LCase([userPrincipalName]),"@techno.ramq.gouv.qc.ca",
"Member",
"Guest"),

"mS-DS-ConsistencyGuid"="mS-DS-ConsistencyGuid"
IIF("domainFQDN" = "@techno.ramq.gouv.qc.ca",
"Member",
"Guest")







IIF(IsPresent([sAMAccountName]) = False 
  || Left([sAMAccountName], 7) = "krbtgt_" 
  || [sAMAccountName] = "SUPPORT_388945a0" 
  || Left([mailNickname], 14) = "SystemMailbox{" 
  || Left([sAMAccountName], 4) = "AAD_" 
  || (Left([mailNickname], 4) = "CAS_" && (InStr([mailNickname], "}") > 0)) 
  || (Left([sAMAccountName], 4) = "CAS_" && (InStr([sAMAccountName], "}") > 0)) 
  || Left([sAMAccountName], 5) = "MSOL_" 
  || CBool(IIF(IsPresent([msExchRecipientTypeDetails]),BitAnd([msExchRecipientTypeDetails],&H21C07000) > 0,NULL)) 
  || CBool(InStr(DNComponent(CRef([dn]),1),"\\0ACNF:")>0)
, True
, NULL)


IIF(IsPresent([userPrincipalName]),
IIF(CBool((InStr(LCase([userPrincipalName]),"@techno.ramq.gouv.qc.ca")=0),"Guest","Member") || CBool((InStr(LCase([userPrincipalName]),"@adtechno.ramq.gouv.qc.ca")=0),"Guest","Member")),
Error("UserPrincipalName is not present to determine UserType"))

IIF(IsPresent([userPrincipalName]),
IIF(CBool((InStr(LCase([userPrincipalName]),"@techno.ramq.gouv.qc.ca")=0),"Guest","Member") || CBool((InStr(LCase([userPrincipalName]),"@adtechno.ramq.gouv.qc.ca")=0),"Guest","Member")),
Error("UserPrincipalName is not present to determine UserType"))