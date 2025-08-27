import Resolver from '@forge/resolver';
import { invokeService } from "@forge/api";

const resolver = new Resolver();

/*
   This is a backend resolver, invoked from the frontend, which must return JSON.
   In this example, we further invoke a container service through the @forge/api package.
 */
resolver.define('invoke-service-resolver', async () => {
    console.log("Calling invokeService...")

    const res = await invokeService('java-service',{
        method: 'POST',
        path: '/invoke-service?exampleStr=jira&exampleInt=123',
        body: JSON.stringify(
            {
                'message': 'Hello from forge app backend'
            }
        ),
        headers: {
            'x-custom-request-header': 'x-custom-request-header-value',
            'Content-Type': 'application/json'
        }
    });

    console.log("Received data from invokeService...: " + res)

    // Transform the APIResponse object into the shape of JSON needed for the InvokeServicePanelComponent
    const headersObj = {};
    res.headers.forEach((val, key) => headersObj[key] = val)
    return {
        status: res.status,
        headers: headersObj,
        body: await res.json()
    };
});

export const handler = resolver.getDefinitions();
