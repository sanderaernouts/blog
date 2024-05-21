---
layout: post
current: post
cover: assets/images/covers/autogenerate-csharp-api-client-with-nswag-splash.jpg
navigation: True
title: Automatically generating C# API clients on build with NSwag
date: 2018-07-20 20:00
author: sander
tags:
  - coding
  - aspnetcore
class: post-template
subclass: 'post'
excerpt: How to automatically generate C# API clients on build for your aspnet core API using NSwag and Swagger.
---
# TL;DR

Want to know how you can generate and compile up to date C# API clients each time you build your solution? Take a look at [this example][5] on GitHub.

Want to generate a Typescript client, check out this [post](./autogenerate-typescript-api-client-with-nswag)

## Background

When you create an API using aspnetcore it is very easy to add a [Swagger][1] endpoint and [SwaggerUI][2] for exploring and testing your API. Once you have [Swagger][1] enabled you can also use the information [Swagger][1] exposes about your API to generate clients for the enpoints and operations your aspnet controllers expose.

With [NSwag][3] you can generate client code without having your API running, many generators require the `swagger.json` file that is exposed when you run your API but [NSwag][3] doesn't.

In this blogpost I will show you how to configure [Swagger][1] an [NSwag][3] so that up to date API clients are generated and compiled each time you build your solution. These clients can be packaged and published through NuGet for easy access to your API's.

## Configure Swagger and SwaggerUI with NSwag

First add the `NSwag.AspNetCore` NuGet package to your API project:

```XML
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>Example.Api</AssemblyName>
    <RootNamespace>Example.Api</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <Folder Include="wwwroot\" />
  </ItemGroup>

  <ItemGroup>
  <PackageReference Include="Microsoft.AspNetCore.Mvc.NewtonsoftJson" Version="3.1.9" />
  <PackageReference Include="NSwag.AspNetCore" Version="14.0.7" />
  <PackageReference Include="NSwag.MSBuild" Version="14.0.7">
    <PrivateAssets>All</PrivateAssets>
  </PackageReference>
</ItemGroup>

</Project>
```

Next add the following code to your `Program.cs`:

```csharp
// .....
builder.Services.AddControllers().AddNewtonsoftJson();
                
builder.Services.AddOpenApiDocument(settings =>
{
    settings.PostProcess = document =>
    {
        document.Info.Version = "v1";
        document.Info.Title = "Example API";
        document.Info.Description = "REST API for example.";
    };
});
//.....

if(!app.Environment.IsProduction()) {
    app.UseOpenApi();
    app.UseSwaggerUi();
}

//......
```

This is enough for a basic [Swagger][1] configuration, if you run your aspnetcore API project and navigate to `http://<host>:<port>/swagger` you will see [SwaggerUI][2]. This will also expose a `swagger.json` document at `http://<host>:<port>/swagger/v1/swagger.json` describing your API.

For more elaborate examples or explanation on how to configure [NSwag][3] have a look at the documentation for [configuring the aspnetcore middleware][7].

## Generate API clients with NSwag

Next setup a separate `Clients` project (or whatever you want to name it) and add the `NSwag.MSBuild` NuGet packages to your API project. We will use this package to generate the code for our API clients after the project is build, this way we regenerate our client code every time you build your project.

There are 2 things you need to add to your API project file to configure this:

- a `PackageReference` to `NSwag.MSBuild` inside a `ItemGroup`
- a custom Target that runs **after** the `Build` target with a `Condition`. This target will invoke `nswag.exe` using an `nswag.json` config file to generate the required code.

Your project file has to look something like this:

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>Example.Api</AssemblyName>
    <RootNamespace>Example.Api</RootNamespace>
  </PropertyGroup>
.....

  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.Mvc.NewtonsoftJson" Version="3.1.9" />
    <PackageReference Include="NSwag.AspNetCore" Version="13.8.2" />
    <PackageReference Include="NSwag.MSBuild" Version="13.8.2">
      <PrivateAssets>All</PrivateAssets>
    </PackageReference>
  </ItemGroup>

  <Target Name="NSwag" BeforeTargets="AfterBuild" Condition="'$(TF_BUILD)'!='True'">
     <Exec 
      ConsoleToMSBuild="true" 
      ContinueOnError="true" 
      Command="$(NSwagExe_Net80) run nswag.json /variables:...">
      <Output TaskParameter="ExitCode" PropertyName="NSwagExitCode"/>
      <Output TaskParameter="ConsoleOutput" PropertyName="NSwagOutput" />
    </Exec>

    <Message Text="$(NSwagOutput)" Condition="'$(NSwagExitCode)' == '0'" Importance="low"/>
    <Error Text="$(NSwagOutput)" Condition="'$(NSwagExitCode)' != '0'"/>
  </Target>
  </Project>
```
*Note that the condition `Condition="'$(TF_BUILD)'!='True'"` is specific to Azure DevOps. This condition ensures that the client code not regenerated. I use this in my Azure DevOps builds so that the version of the code that is in source control is used instead of being regenerated. You can use any environment variable while running MSBuild. So if you are using a different CI system which sets a different environment variable you can use that instead. Else you can introduce your own MSBuild variable in the `PropertyGroup` and pass that to `dotnet.exe` using `/p:MyVar=False`*

The `NSwag` target is configured to log the output of `nswag.exe` as MSBuild messages. If the exit code is anything but 0 and `Error` message will be logs. It took me a while to figure this out but this way you can see in your MSBuild output why `nswag.exe` is failing.

The easiest way to create a `nswag.json` config file is by using [NSwagStudio][4] which you can install on Windows using an `MSI` you can find [here][4] or you can take the `nswag.json` file from my [example repository on github][5] and make modifications in that.

Below are the most important properties for this example (get the full `nswag.json` file [here][5]):

```json
{
  "runtime": "Net80",
  "documentGenerator": {
    "aspNetCoreToOpenApi": {
      ...
      "aspNetCoreEnvironment": "CodeGeneration",
      ...
    }
  }, 
  "codeGenerators": {
    "openApiToCSharpClient": {
      "clientBaseClass": null,
      "generateClientClasses": true,
      "generateClientInterfaces": true,
      "clientBaseInterface": null,
      "injectHttpClient": true,
      "disposeHttpClient": false,
      "output": "$(CSharpOutputPath)/Client.g.cs",
      "contractsOutputFilePath": "$(CSharpOutputPath)/Contracts.g.cs",
    }
  }
}
```

The `documentGenerator.aspNetCoreToOpenApi.aspNetCoreEnvironment` is especially important because ASP.net core uses `Production` as the default environment. If you something like this in your code:

```csharp
if(!app.Environment.IsProduction()) {
    app.UseOpenApi();
    app.UseSwaggerUi();
}
```

Then the OpenAPI and Swagger endpoints are only available when the environment is set to something other than `Production`.

Make sure you set `generateClientClasses`, `generateClientInterfaces`, and `injectHttpClient`. Make sure you set `disposeHttpClient` to `false` if you use a dependency injection container to handle the lifetime of your `HttpClient`. The `output` and `contractsOutputFilePath` parameters use the `CSharpOutputPath` to place the generated code in the `Client` project instead of the `Api` project.

You can use the [IHttpClientFactory](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/http-requests?view=aspnetcore-8.0) in .NET Core to configure the `HttpClient` (this is why you have to set `injectHttpClient` to `true`). You can also add [extra behavior](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/http-requests?view=aspnetcore-8.0#outgoing-request-middleware) such as retries (with [Polly](https://docs.microsoft.com/en-us/aspnet/core/fundamentals/http-requests?view=aspnetcore-8.0#outgoing-request-middleware)).

Now build the `Api` project to generate the clients and contracts and the build your `Client` project. All that is left to do is to package your `Client` project as a NuGet package and share it with the users of your API. Having the `Client` project in the same solution as your aspnetcore API allows you to automatically build and publish up to date clients for your API.

A fully [working example][5] is available on GitHub. If you encounter issues with this example create an issue on that repository or leave a comment here.

[NSwag][3] has a bunch of options to customize and tweak how the clients and contracts are generated. I have only shown you a very basic example. For example [NSwag][3] can also generate `Typescript` clients. Take a look at the [wiki][6] for [NSwag][3] if you want to know how to do this and what else [NSwag][3] can do.

Want to generate a Typescript client, check out this [post](./autogenerate-typescript-api-client-with-nswag)

*NOTE: I used to do this the other way around, meaning that the `Client` project contained the NSwag MSBuild target. This caused quite some build errors when concurrently building because the `Client` project had an implicit dependency on the `Api` project. So I decided to swap it around and make the `Api` project generate the code into the `Client` project instead.*

*Theoretically the generated code can get out of sync when the `Client` project builds before the `Api` project. But, to generated a changed client you will always have to modify the `Api` project first to add or modify some `Controller`. So as soon as you compile those changes the `Client` project will be updated. In short, this should never happen in practice. There is an MSBuild "trick" to ensure the correct build order without adding an assembly reference to the `Api` project but as said, you shouldn't need that.*

## Credits

Thanks to my colleague [Erick Segaar](https://www.ericksegaar.com/) for providing the updated code for ASP.net core 8 and NSwag 14.

Cover photo by <a style="background-color:black;color:white;text-decoration:none;padding:4px 6px;font-family:-apple-system, BlinkMacSystemFont, &quot;San Francisco&quot;, &quot;Helvetica Neue&quot;, Helvetica, Ubuntu, Roboto, Noto, &quot;Segoe UI&quot;, Arial, sans-serif;font-size:12px;font-weight:bold;line-height:1.2;display:inline-block;border-radius:3px" href="https://unsplash.com/@modestasu?utm_medium=referral&amp;utm_campaign=photographer-credit&amp;utm_content=creditBadge" target="_blank" rel="noopener noreferrer" title="Download free do whatever you want high-resolution photos from Modestas Urbonas"><span style="display:inline-block;padding:2px 3px"><svg xmlns="http://www.w3.org/2000/svg" style="height:12px;width:auto;position:relative;vertical-align:middle;top:-1px;fill:white" viewBox="0 0 32 32"><title>unsplash-logo</title><path d="M20.8 18.1c0 2.7-2.2 4.8-4.8 4.8s-4.8-2.1-4.8-4.8c0-2.7 2.2-4.8 4.8-4.8 2.7.1 4.8 2.2 4.8 4.8zm11.2-7.4v14.9c0 2.3-1.9 4.3-4.3 4.3h-23.4c-2.4 0-4.3-1.9-4.3-4.3v-15c0-2.3 1.9-4.3 4.3-4.3h3.7l.8-2.3c.4-1.1 1.7-2 2.9-2h8.6c1.2 0 2.5.9 2.9 2l.8 2.4h3.7c2.4 0 4.3 1.9 4.3 4.3zm-8.6 7.5c0-4.1-3.3-7.5-7.5-7.5-4.1 0-7.5 3.4-7.5 7.5s3.3 7.5 7.5 7.5c4.2-.1 7.5-3.4 7.5-7.5z"></path></svg></span><span style="display:inline-block;padding:2px 3px">Modestas Urbonas</span></a>

## Updates

- 21/04/2024: upgraded to ASP.net core 8, NSwag 14, and added a note about the `aspNetCoreEnvironment` property in `nswag.json`.
- 25/10/2020: upgraded to ASP.net core 3.1, moved client generation to Api project, and added output logging to MSBuild.
- 02/11/2019: updated examples to aspnetcore 3.0 and NSwag 13.
- 13/02/2019: updated examples to aspnetcore 2.2 and NSwag 12.

[1]: https://swagger.io/
[2]: https://swagger.io/tools/swagger-ui/
[3]: https://github.com/RSuter/NSwag
[4]: https://github.com/RSuter/NSwag/wiki/NSwagStudio
[5]: https://github.com/sanderaernouts/autogenerate-api-client-with-nswag
[6]: https://github.com/RSuter/NSwag/wiki
[7]: https://github.com/RSuter/NSwag/wiki/AspNetCore-Middleware