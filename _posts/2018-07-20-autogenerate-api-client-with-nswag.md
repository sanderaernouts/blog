---
layout: post
current: post
cover: assets/images/covers/autogenerate-api-client-with-nswag-splash.jpg
navigation: True
title: Automatically generating API clients on build with NSwag
date: 2018-07-20 20:00
author: sander
tags:
  - coding
  - aspnetcore
class: post-template
subclass: 'post'
excerpt: How to automatically generate API clients on build for your aspnet core API using NSwag and Swagger.
---
# TL;DR;

Want to know how you can generate and compile up to date API clients each time you build your solution? Take a look at [this example][5] on GitHub.

## Background

When you create an API using aspnetcore it is very easy to add a [Swagger][1] endpoint and [SwaggerUI][2] for exploring and testing your API. Once you have [Swagger][1] enabled you can also use the information [Swagger][1] exposes about your API to generate clients for the enpoints and operations your aspnet controllers expose.

With [NSwag][3] you can generate client code without having your API running, many generators require the `swagger.json` file that is exposed when you run your API but [NSwag][3] doesn't.

In this blogpost I will show you how to configure [Swagger][1] an [NSwag][3] so that up to date API clients are generated and compiled each time you build your solution. These clients can be packaged and published through NuGet for easy access to your API's.

## Configure Swagger and SwaggerUI with NSwag

First add the `NSwag.AspNetCore` NuGet package to your API project:

```XML
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>netcoreapp2.2</TargetFramework>
    <AssemblyName>Example.Api</AssemblyName>
    <RootNamespace>Example.Api</RootNamespace>
    <AspNetCoreHostingModel>InProcess</AspNetCoreHostingModel>
  </PropertyGroup>

  <ItemGroup>
    <Folder Include="wwwroot\" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.App" />
    <PackageReference Include="NSwag.AspNetCore" Version="12.0.13" />
  </ItemGroup>

</Project>
```

Next add the following code to your `Startup.cs`:

```csharp
// This method gets called by the runtime. Use this method to add services to the container.
public void ConfigureServices(IServiceCollection services)
{
  // .....
    services.AddMvc().SetCompatibilityVersion(CompatibilityVersion.Version_2_2);

    services.AddSwaggerDocument(settings =>
    {
        settings.PostProcess = document =>
        {
            document.Info.Version = "v1";
            document.Info.Title = "Example API";
            document.Info.Description = "REST API for example.";
        };
    });
    //.....
}

// This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
public void Configure(IApplicationBuilder app, IHostingEnvironment env)
{
    // .....
    // Enable the Swagger UI middleware and the Swagger generator
    app.UseSwagger();
    app.UseSwaggerUi3();
    // .....
}
```

This is enough for a basic [Swagger][1] configuration, if you run your aspnetcore API project and navigate to `http://<host>:<port>/swagger` you will see [SwaggerUI][2]. This will also expose a `swagger.json` document at `http://<host>:<port>/swagger/v1/swagger.json` describing your API.

For more eloborate examples or explanation on how to configure [NSwag][3] have a look at the documentation for [configuring the aspnetcore middleware][7].

## Generate API clients with NSwag

Next setup a seperate `Clients` project (or whatever you want to name it) and add the `NSwag.MSBuild` NuGet packages to it. We will use this package to generate the code for our API clients before the project is build, this way we can generate our code and compile it everytime you build your project.

There are 3 things you need to add to your project file to config this:

- an MSBuild property called `GenerateCode` inside a `PropertyGroup` with the value `True`
- a `PackageReference` to `NSwag.MSBuild` insid a `ItemGroup`
- a custom Target that runs **before** the `PrepareForBuild` target with a `Condition`. This target will invoke `nswag.exe` using an `nswag.json` config file to generate the required code.

Your project file has to look something like this:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>netstandard2.0</TargetFramework>
    <AssemblyName>Example.Api.Client</AssemblyName>
    <RootNamespace>Example.Api.Client</RootNamespace>
    <GenerateCode>True</GenerateCode>
  </PropertyGroup>
<ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="9.0.1" />
    <PackageReference Include="NSwag.MSBuild" Version="12.0.13">
      <PrivateAssets>All</PrivateAssets>
    </PackageReference>
  </ItemGroup>
  
  <Target Name="NSwag" BeforeTargets="PrepareForBuild" Condition="'$(GenerateCode)'=='True' ">
    <Exec Command="$(NSwagExe_Core22) run nswag.json /variables:Configuration=$(Configuration)" />
  </Target>
</Project>
```

You can pass `/p:GenerateCode=False` to `dotnet.exe` when building to disable the code generation. I use this on the CI server so that the version of the code that is in source controll will be used instead of being regenerated.

The easiest way to create a `nswag.json` config file is by using [NSwagStudio][4] which you can install on Windows using an `MSI` you can find [here][4] or you can take the `nswag.json` file from my [example repository on github][5] and make modifications in that.

Below are the most important properties for this example (get the full `nswag.json` file [here][5]):

```json
{
    "runtime": "NetCore22",
    "defaultVariables": null,
    "swaggerGenerator": {
        "aspNetCoreToSwagger": {
            "project": "../Api/Api.csproj", //path to your aspnetcore 2.1 project
            //...
        }
    },
    "codeGenerators": {
        "swaggerToCSharpClient": {
            "clientBaseClass": "ClientBase", //name of your client base class
            "configurationClass": null,
            "generateClientClasses": true,
            "generateClientInterfaces": true,
            ...
            "useHttpRequestMessageCreationMethod": true, //allows you to add headers to each message
            "clientClassAccessModifier": "internal", //make client generated client implementations internal
            "typeAccessModifier": "public", //make your models and client interfaces public
            "generateContractsOutput": true, //generate contacts in a separte file
            "contractsNamespace": "Example.Api.Client.Contracts", //contracts namespace
            "contractsOutputFilePath": "Contracts.g.cs",
            ...
            "namespace": "Example.Api.Client", //clients namespace
            ...
            "output": "Client.g.cs"
        }
    }
}
```

The most important part is the `useHttpRequestMessageCreationMethod` and `clientBaseClass`, this allows you to define a base class in your `Client` project that will create the `HttpMessage` that your clients will send. This allows you to for example add an `Authorization` header with a `Bearer` token. The client base class below does just that:

```csharp
internal abstract class ClientBase
  {
      public Func<Task<string>> RetrieveAuthorizationToken { get; set; }

      // Called by implementing swagger client classes
      protected async Task<HttpRequestMessage> CreateHttpRequestMessageAsync(CancellationToken cancellationToken)
      {
          var msg = new HttpRequestMessage();

          if (RetrieveAuthorizationToken != null)
          {
              var token = await RetrieveAuthorizationToken();
              msg.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
          }
          return msg;
      }

  }
```

I chose for a `Func<..>` in my base class to retrieve the `Bearer` token. This `Func<..>` is invoked each time a message is created, this way the code that uses your client can contain logic to retrieve a new token when the  current one is expired.

Also I made my client implementations `internal` and expose a `public` interfaces. For this to work you will have to add a `public` factory or some other `public` mechanism to create instances of your clients. Here is an example of my factory:

```csharp
public static class ClientFactory
  {
      public static IValuesClient CreateValuesClient(string baseUrl, HttpClient http, Func<Task<string>> retrieveAuthorizationToken)
      {
          return new ValuesClient(baseUrl, http)
          {
              RetrieveAuthorizationToken = retrieveAuthorizationToken
          };
      }
  }
```

Now build the `Client` project to generate the clients and contracts. All that is left to do is to package your `Client` project as a NuGet package and share it with the users of your API. Having the `Client` project in the same solution as your aspnetcore API allows you to automatically build and publish up to date clients for your API.

A fully [working example][5] is available on GitHub. If you encounter issues with this example create an issue on that repository or leave a comment here.

[NSwag][3] has a bunch of options to customize and tweak how the clients and contracts are generated. I have only shown you a very basic example. For example [NSwag][3] can also generate `Typescript` clients. Take a look at the [wiki][6] for [NSwag][3] if you want to know how to do this and what else [NSwag][3] can do.

## Credits

Cover photo by <a style="background-color:black;color:white;text-decoration:none;padding:4px 6px;font-family:-apple-system, BlinkMacSystemFont, &quot;San Francisco&quot;, &quot;Helvetica Neue&quot;, Helvetica, Ubuntu, Roboto, Noto, &quot;Segoe UI&quot;, Arial, sans-serif;font-size:12px;font-weight:bold;line-height:1.2;display:inline-block;border-radius:3px" href="https://unsplash.com/@modestasu?utm_medium=referral&amp;utm_campaign=photographer-credit&amp;utm_content=creditBadge" target="_blank" rel="noopener noreferrer" title="Download free do whatever you want high-resolution photos from Modestas Urbonas"><span style="display:inline-block;padding:2px 3px"><svg xmlns="http://www.w3.org/2000/svg" style="height:12px;width:auto;position:relative;vertical-align:middle;top:-1px;fill:white" viewBox="0 0 32 32"><title>unsplash-logo</title><path d="M20.8 18.1c0 2.7-2.2 4.8-4.8 4.8s-4.8-2.1-4.8-4.8c0-2.7 2.2-4.8 4.8-4.8 2.7.1 4.8 2.2 4.8 4.8zm11.2-7.4v14.9c0 2.3-1.9 4.3-4.3 4.3h-23.4c-2.4 0-4.3-1.9-4.3-4.3v-15c0-2.3 1.9-4.3 4.3-4.3h3.7l.8-2.3c.4-1.1 1.7-2 2.9-2h8.6c1.2 0 2.5.9 2.9 2l.8 2.4h3.7c2.4 0 4.3 1.9 4.3 4.3zm-8.6 7.5c0-4.1-3.3-7.5-7.5-7.5-4.1 0-7.5 3.4-7.5 7.5s3.3 7.5 7.5 7.5c4.2-.1 7.5-3.4 7.5-7.5z"></path></svg></span><span style="display:inline-block;padding:2px 3px">Modestas Urbonas</span></a>

## Updates

- 02/13/2019: updated examples to aspnetcore 2.2 and NSwag 12.

[1]: https://swagger.io/
[2]: https://swagger.io/tools/swagger-ui/
[3]: https://github.com/RSuter/NSwag
[4]: https://github.com/RSuter/NSwag/wiki/NSwagStudio
[5]: https://github.com/sanderaernouts/autogenerate-api-client-with-nswag
[6]: https://github.com/RSuter/NSwag/wiki
[7]: https://github.com/RSuter/NSwag/wiki/AspNetCore-Middleware