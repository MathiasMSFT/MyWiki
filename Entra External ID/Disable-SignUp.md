# How to disable SignUp flow in Entra External ID (external tenant)
By default, you can not disable the signup process through the portal. If you want to do that, you have to use Graph.


## Documentation
In Microsoft docuemntation, you will be to see that UserFlow doesn't exist, but authenticationEventsFlow exists.

https://learn.microsoft.com/en-us/graph/api/resources/authenticationeventsflow?view=graph-rest-beta


## List your authenticationEventsFlow

The first step consists to list all flows
![alt text](image-13.png)

 For each flow, you can see the id, displayName, priority, idp, ...
As you can see, the SignUp process is true
![alt text](image-14.png)

To modify this value, you need to get the id of this authenticationEventsFlow
![alt text](image-15.png)

## Disable the SignUp
With the id, you will be able to PATCH the configuration

Add headers
![alt text](image-16.png)

Request body
![alt text](image-17.png)

![alt text](image-18.png)


Now, validate your configuration through a GET
![alt text](image-19.png)


