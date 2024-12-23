# Table of Contents
- [Introduction](#introduction)
- [Personas](#Personas)
    - [What is the definition](#what-is-the-definition)
    - [What is the utility of Personas in Zero Trust](#What-is-the-utility-of-Personas-in-Zero-Trust)
    - [Mind Map](#Mind-Map)
- [Conditional Access](#Conditional-Access)


# Introduction

Zero Trust for Identity means you should trust nobody. But how to implement this principle ? This a question that I hear a lot.
In this repo, we will see what you have to include and what are changes you have to implement.
We will also our Microsoft solutions can be used to attempt your goal.

In Microsoft documentation, a concept that already exist since many years, come back. Personas !!! But what does it mean ?
And before starting to build your rules, start with Personas.


# Personas
In the context of implementing Zero Trust for identity, a persona refers to a typical profile representing a category of users within an organization. This concept is essential to determine appropriate security policies and access levels for different groups of users based on their roles, responsibilities, and behaviors.

## What is the definition
A persona is generaly represented by a group of users sharing common characteristics. Lot of organisations know that, but start directly with line of business (trader, etc), type of role/job. They often forgot that all of them have a common point: they are employees.

You can have different level, but you should define the first level.

Here are some personas:
- Employees or internals: you have the same employer on your paid check.
- Externals or consultants: they are not directly paid by your organisation but they work for you. They need an account and/or a computer managed by your organisation.
- Guests: they need to collaborate with your organisation, but it's not required for them to use a corporate computer or having a corporate identity.
- Admins: administrators should have a specific account and some 
- Developers:
- Generic Account:
- Service Accounts:
This list is non-exaustive and you should define your own persona based on the common characteristics.

To help you designing your personas, use this guidance. Personas have common:
- Goals
- Behaviors
- Security needs
- Resource access

## What is the utility of Personas in Zero Trust
The Zero Trust approach is based on the principle that nothing should be trusted, whether inside or outside your network organization.

Personas help to:
- Define Access Policies: By determining the specific needs of each group, it is possible to create granular access policies based on identity.
- Implement Continuous Authentication: By monitoring typical behaviors of personas, systems can detect and respond to anomalies in real-time.
- Reduce Risks: By limiting access to only the necessary resources for each persona, the potential attack surface is minimized.
- Facilitate Access Management: Personas simplify the administration of access rights by allowing group-based rather than individual management.

## Mind Map

Your first level:
<p align="center" width="100%">
    <img width="70%" src="./images/personas/List-of-personas-1.png">
</p>

Your second level:
<p align="center" width="100%">
    <img width="70%" src="./images/personas/List-of-personas-2.png">
</p>



# Conditional Access


# Identity Governance (in progress)


# Purview (in progress)


