# Consent


## Configuration

### Low

<p align="center" width="100%">
    <img width="70%" src="./images/Permissions-Classification-Low.png">
</p>

### Medium

<p align="center" width="100%">
    <img width="70%" src="./images/Permissions-Classification-Medium.png">
</p>



## Scope: openid + profile + group.read

Get token with this scope:
- openid
- profile
- group.read

```
https://login.microsoftonline.com/<tenantid>/oauth2/v2.0/authorize?client_id=<clientid>&nonce=defaultNonce&redirect_uri=https%3A%2F%2Fjwt.ms&scope=openid+profile+group.read&response_type=token
```

<p align="center" width="100%">
    <img width="70%" src="./images/UserConsent-NotClassified.png">
</p>



## Scope: openid + profile

Get token with this scope:
- openid
- profile

```
https://login.microsoftonline.com/<tenantid>/oauth2/v2.0/authorize?client_id=<clientid>&nonce=defaultNonce&redirect_uri=https%3A%2F%2Fjwt.ms&scope=openid+profile&response_type=token
```
<p align="center" width="100%">
    <img width="70%" src="./images/UserConsent-Low-1.png">
</p>

User was able to consent because this is an application I registered and scope match with my low permission definition.
<p align="center" width="100%">
    <img width="70%" src="./images/JWT-Low-1.png">
</p>


## Scope: openid + profile + user.readwrite

Get token with this scope:
- openid
- profile
- user.readwrite
```
https://login.microsoftonline.com/<tenantid>/oauth2/v2.0/authorize?client_id=<clientid>&nonce=defaultNonce&redirect_uri=https%3A%2F%2Fjwt.ms&scope=openid+profile+user.readwrite&response_type=token
```

**Admin consent is required !!**

<p align="center" width="100%">
    <img width="70%" src="./images/UserConsent-Medium-1.png">
</p>

Only "low impact" is supported.

<p align="center" width="100%">
    <img width="70%" src="./images/UserConsent-options.png">
</p>




