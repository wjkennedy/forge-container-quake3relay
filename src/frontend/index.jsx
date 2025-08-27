import React, { useEffect, useState } from 'react';
import ForgeReconciler, { Text } from '@forge/react';
import { invokeService, __realtime } from '@forge/bridge';
import InvokeServicePanelComponent from "./InvokeServicePanelComponent";

/*
   In this example, we directly invoke a container service through the @forge/bridge package.
 */
const App = () => {
    const [data, setData] = useState(null);
    const [realtimeData, setRealtimeData] = useState(null);

    useEffect(() => {
        console.log("Calling POST /invoke-service ...")

        const fetchData = async () => {
            const data = await invokeService({
                method: 'POST',
                path: '/invoke-service?exampleStr=jira&exampleInt=123',
                body: JSON.stringify(
                    {
                        'message': 'Hello from forge app frontend'
                    }
                ),
                headers: {
                    'x-custom-request-header': 'x-custom-request-header-value'
                }
            });
            console.log(`POST /invoke-service response: ${JSON.stringify(data, null, 2)}`)
            setData(data);
        }

        fetchData()
    }, []);

    useEffect(() => {
        // This subscribes to a channel called "forge-container-realtime-channel", the "webtrigger-realtime" endpoint will publish to this channel.
        const subscribeToTopic = async () => {
            const onEvent = (payload) => {
                console.log('Received event with payload...: ', payload);
                setRealtimeData(payload);
            };
            const subscription = await __realtime.subscribe('forge-container-realtime-channel', onEvent);
            console.log('Subscribed to channel: forge-container-realtime-channel', subscription);
        }

          subscribeToTopic();
    }, []);



    return (
        <>
            <Text>Realtime event received: {JSON.stringify(realtimeData, null, 2)}</Text>
            <InvokeServicePanelComponent data={data} />
        </>
    )
};

ForgeReconciler.render(
    <React.StrictMode>
        <App/>
    </React.StrictMode>
);
