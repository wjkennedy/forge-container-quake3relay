import React, { useEffect, useState } from "react";
import ForgeReconciler, { Text } from "@forge/react";
import { invokeService, realtime } from "@forge/bridge";
import InvokeServicePanelComponent from "./InvokeServicePanelComponent";

/*
   In this example, we directly invoke a container service through the @forge/bridge package.
 */
const App = () => {
    const [data, setData] = useState(null);
    const [realtimeData, setRealtimeData] = useState(null);
    const [globalRealtimeData, setGlobalRealtimeData] = useState(null);
    const [globalTokenRealtimeData, setGlobalTokenRealtimeData] = useState(null);
    const [offlineAccessRealtimeData, setOfflineAccessRealtimeData] = useState(null);

    useEffect(() => {
        console.log("Calling POST /invoke-service ...");

        const fetchData = async () => {
            const data = await invokeService({
                method: "POST",
                path: "/invoke-service?exampleStr=jira&exampleInt=123",
                body: JSON.stringify({
                    message: "Hello from forge app frontend",
                }),
                headers: {
                    "x-custom-request-header": "x-custom-request-header-value",
                },
            });
            console.log(`POST /invoke-service response: ${JSON.stringify(data, null, 2)}`);
            setData(data);
        };

        fetchData();
    }, []);

    // This subscribes to a channel
    // A message will be sent to this channel using invokeService so that it comes from the same context.
    useEffect(() => {
        const channelName = "forge-container-realtime-channel";
        const subscribeToChannel = async () => {
            const onEvent = (payload) => {
                console.log("Received event with payload...: ", payload);
                setRealtimeData(payload);
            };
            const subscription = await realtime.subscribe(channelName, onEvent);
            console.log(`Subscribed to channel: ${channelName}`, subscription);

            // Wait a moment to ensure subscription is established
            await new Promise((resolve) => setTimeout(resolve, 2000));

            // Publish a message to this channel via invoke service
            console.log("Invoking service to publish realtime message...");
            const resp = await invokeService({
                method: "POST",
                path: "/publish-realtime-message",
                body: JSON.stringify({
                    channelName: channelName,
                }),
                headers: {
                    "x-custom-request-header": "x-custom-request-header-value",
                    "Content-Type": "application/json",
                },
            });
            console.log("Publish realtime message response: ", resp);
        };

        subscribeToChannel();
    }, []);

    // This subscribes to a global channel
    // the 'webtrigger/realtime/global' endpoint will publish to this channel.
    useEffect(() => {
        const channelName = "forge-container-global-realtime-channel";
        const subscribeToGlobalChannel = async () => {
            const onEvent = (payload) => {
                console.log("Received event with payload...: ", payload);
                setGlobalRealtimeData(payload);
            };
            const subscription = await realtime.subscribeGlobal(
                channelName,
                onEvent
            );
            console.log(`Subscribed to channel: ${channelName}`, subscription);
        };

        subscribeToGlobalChannel();
    }, []);

    // This subscribes to a global channel with a token
    // The 'webtrigger/realtime/token' endpoint will publish to this channel.
    useEffect(() => {
        const channelName = "forge-container-global-token-realtime-channel";
        const subscribeToGlobalTokenChannel = async () => {
            const onEvent = (payload) => {
                console.log(
                    "Received tokened event with payload...: ",
                    payload
                );
                setGlobalTokenRealtimeData(payload);
            };

            console.log("Requesting a signed realtime token from backend...");
            const realtimeTokenResponse = await invokeService({
                method: "POST",
                path: "/sign-realtime-token",
                body: JSON.stringify({
                    channelName: channelName,
                    claims: {
                        allowedUsers: ["accountId-1", "accountId-2"],
                    },
                }),
                headers: {
                    "x-custom-request-header": "x-custom-request-header-value",
                    "Content-Type": "application/json",
                },
            });

            const signedRealtimeToken = realtimeTokenResponse.body.signedRealtimeToken;
            const tokenPreview = `${signedRealtimeToken.substring(0, 6)}...${signedRealtimeToken.substring(
                signedRealtimeToken.length - 6
            )}`;
            console.log("Received signed realtime token: ", tokenPreview);

            const subscription = await realtime.subscribeGlobal(
                channelName,
                onEvent,
                { token: signedRealtimeToken }
            );
            console.log(`Subscribed to channel: ${channelName}`, subscription);
        };

        subscribeToGlobalTokenChannel();
    }, []);

    // This subscribes to a channel which a realtime event is sent to every 15 seconds using offline access
    useEffect(() => {
        const channelName = "offline-access-global-realtime-channel";
        const subscribeToOfflineAccessGlobalChannel = async () => {
            const onEvent = (payload) => {
                console.log("Received offline access event with payload...: ", payload);
                setOfflineAccessRealtimeData(payload);
            };
            const subscription = await realtime.subscribeGlobal(
                channelName,
                onEvent
            );
            console.log(`Subscribed to offline access channel: ${channelName}`, subscription);
        };

        subscribeToOfflineAccessGlobalChannel();
    }, []);

    return (
        <>
            <Text>
                Realtime event received: {JSON.stringify(realtimeData, null, 2)}
            </Text>
            <Text>
                Global realtime event received: {JSON.stringify(globalRealtimeData, null, 2)}
            </Text>
            <Text>
                Global tokened realtime event received: {JSON.stringify(globalTokenRealtimeData, null, 2)}
            </Text>
            <Text>
                Offline access realtime event received: {JSON.stringify(offlineAccessRealtimeData, null, 2)}
            </Text>
            <InvokeServicePanelComponent data={data} />
        </>
    );
};

ForgeReconciler.render(
    <React.StrictMode>
        <App />
    </React.StrictMode>
);
