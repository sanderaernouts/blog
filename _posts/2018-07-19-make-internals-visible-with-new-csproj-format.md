---
layout: post
current: post
cover: assets/images/covers/make-internals-visible-with-new-csproj-format-splash.jpg
navigation: True
title: How to make internal members visible to other assemblies with the new CSPROJ format
date: 2018-07-19 20:00
author: sander
tags:
  - coding
class: post-template
subclass: 'post'
description: How to add the InternalsVisibleTo attribute to your generated AssemblyInfo.cs when using the new CSPROJ 
---
# TL;DR

Add this snippet to your project file:

```xml
<ItemGroup>
    <AssemblyAttribute Include="System.Runtime.CompilerServices.InternalsVisibleTo">
      <_Parameter1>$(AssemblyName).Tests</_Parameter1>
    </AssemblyAttribute>
  </ItemGroup>
```

## Background

Then "new" CSPROJ format has been arround for while already. One of the big differences with the previous CSPROJ format is that your project file now only contains the minimal required configuration for your project and everything is `MSBuild` based now. NuGet packages are referenced through `<PackageReference>` elements and your `AssemblyInfo.cs` is generate based on the properties set in your project file. On build the real `.csproj` file is generated based by MSBuild your project file. For example this enough for a simple netstandard 2.0 class library project:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <AssemblyName>MyProject</AssemblyName>
    <RootNamespace>MyProject</RootNamespace>
  </PropertyGroup>
</Project>
```

Having MSBuild generating the real `.csproj` allows you to edit the your project file without unloading the project and you no longer have to include for example `.cs` files. By default all `.cs` files in the project folder are inlcuded.

But in the past you will have done something like this to allow your unit test project to access internal members in the tested project:

```csharp
using System;
using System.Reflection;

[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("MyProject.Tests")]
[assembly: System.Reflection.AssemblyCompanyAttribute("MyProject")]
[assembly: System.Reflection.AssemblyConfigurationAttribute("Debug")]
[assembly: System.Reflection.AssemblyFileVersionAttribute("1.0.0.0")]
[assembly: System.Reflection.AssemblyInformationalVersionAttribute("1.0.0")]
[assembly: System.Reflection.AssemblyProductAttribute("MyProject")]
[assembly: System.Reflection.AssemblyTitleAttribute("MyProject")]
[assembly: System.Reflection.AssemblyVersionAttribute("1.0.0.0")]
```

However with the new CSPROJ format you do not have an `AssemblyInfo.cs` file anymore as part of your project. You can add one but then you may run into trouble when attributes are specified twice because MSBuild will still generated a `MyProject.AssemblyInfo.cs` file in your projects `obj\` folder. You can disable `AssemblyInfo.cs` generation by adding this to your project file:

```xml
<PropertyGroup>
   <GenerateAssemblyInfo>false</GenerateAssemblyInfo>
</PropertyGroup> 
```

That works but it means you will have to add all of the assembly attributes there. A far nicer solution in my opinion is adding the following to your project file instead:
```xml
<ItemGroup>
    <AssemblyAttribute Include="System.Runtime.CompilerServices.InternalsVisibleTo">
      <_Parameter1>$(AssemblyName).Tests</_Parameter1>
    </AssemblyAttribute>
  </ItemGroup>
```

This snippet will add an `[assembly: System.Runtime.CompilerServices.InternalsVisibleTo("MyProject.Tests")]` to your generated `obj\MyProject.AssemblyInfo.cs` file. Assuming the assemblyname of your project is `MyProject`. You can add any value as input for `<_Parameter1>` and you can use MSBuild variables there as well.